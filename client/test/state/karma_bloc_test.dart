import 'package:civic_commons/karma/data/karma_event_records.dart';
import 'package:civic_commons/karma/data/local_karma_repository.dart';
import 'package:civic_commons/karma/domain/karma_action.dart';
import 'package:civic_commons/karma/domain/karma_gate.dart';
import 'package:civic_commons/repository/domain/entity_store.dart';
import 'package:civic_commons/karma/domain/karma_event.dart';
import 'package:civic_commons/state/data/local_karma_bloc.dart';
import 'package:civic_commons/state/domain/karma_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemStore<T> implements EntityStore<T> {
  final String Function(T) _idOf;
  final Map<String, T> _items = {};

  _MemStore(this._idOf);

  @override
  Future<void> insert(T entity) async {
    _items[_idOf(entity)] = entity;
  }

  @override
  Future<void> update(T entity) async {
    _items[_idOf(entity)] = entity;
  }

  @override
  Future<void> delete(String id) async {
    _items.remove(id);
  }

  @override
  Future<T?> getById(String id) async => _items[id];

  @override
  Future<List<T>> getAll() async => List.unmodifiable(_items.values);
}

String _hash(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  late _MemStore<KarmaEventRecord> store;
  late LocalKarmaRepository repository;
  late LocalKarmaBloc bloc;

  setUp(() {
    store = _MemStore<KarmaEventRecord>((r) => r.eventId);
    repository = LocalKarmaRepository(store: store);
    bloc = LocalKarmaBloc(
      repository: repository,
      accountAgeDays: 120,
      localActorHash: () async => _hash(1),
    );
  });

  tearDown(() => bloc.close());

  test('refresh transitions loading → ready with balance + gates', () async {
    final states = <KarmaState>[];
    final sub = bloc.state.listen(states.add);
    await bloc.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(states.first.isLoading, isTrue);
    final ready = states.last;
    expect(ready.isReady, isTrue);
    expect(ready.balance, 0);
    expect(ready.satisfied(KarmaGate.skipProbationPosting), isFalse);
    await sub.cancel();
  });

  test('record appends and refreshes to the new balance', () async {
    expect(await bloc.record(KarmaAction.academyModuleCompleted), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(bloc.current.isReady, isTrue);
    expect(bloc.current.balance, 2);
    expect(bloc.current.activity, hasLength(1));
    expect(bloc.current.activity.single.action,
        KarmaAction.academyModuleCompleted);

    expect(await bloc.record(KarmaAction.ledgerPostVerified), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(bloc.current.balance, 7);
  });

  test('gates projection respects score + tenure', () async {
    // Seed to 100 karma via 20 verified posts.
    for (var i = 0; i < 20; i++) {
      await bloc.record(KarmaAction.ledgerPostVerified);
    }
    await Future<void>.delayed(Duration.zero);
    final state = bloc.current;
    expect(state.balance, 100);
    expect(state.satisfied(KarmaGate.skipProbationPosting), isTrue);
    expect(state.satisfied(KarmaGate.peerReviewVoting), isTrue);
    expect(state.satisfied(KarmaGate.warRoomAnalystEligibility), isFalse);
    // accountAgeDays = 120 → tenure met, but score (100) < 500.
    expect(state.satisfied(KarmaGate.moderatorCouncil), isFalse);
  });

  test('moderator council gate requires tenure (bloc-level)', () async {
    final youngBloc = LocalKarmaBloc(
      repository: repository,
      accountAgeDays: 10, // tenure short
      localActorHash: () async => _hash(1),
    );
    for (var i = 0; i < 100; i++) {
      await youngBloc.record(KarmaAction.ledgerPostVerified);
    }
    await Future<void>.delayed(Duration.zero);
    expect(youngBloc.current.balance, 500);
    expect(youngBloc.current.satisfied(KarmaGate.moderatorCouncil), isFalse);
    await youngBloc.close();
  });

  test('a repository failure degrades to a generic payload-free error',
      () async {
    final failing = FailingKarmaRepository();
    final failingBloc = LocalKarmaBloc(
      repository: failing,
      accountAgeDays: 0,
      localActorHash: () async => _hash(1),
    );
    final states = <KarmaState>[];
    final sub = failingBloc.state.listen(states.add);
    await failingBloc.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(failingBloc.current.isError, isTrue);
    expect(failingBloc.current.errorMessage, isNotEmpty);
    expect(failingBloc.current.balance, 0);
    await sub.cancel();
    await failingBloc.close();
  });

  test('a malformed local actor makes record reject cleanly (no error state)',
      () async {
    final badBloc = LocalKarmaBloc(
      repository: repository,
      accountAgeDays: 0,
      localActorHash: () async => 'not-a-hash',
    );
    expect(await badBloc.record(KarmaAction.ledgerPostVerified), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(badBloc.current.isReady, isFalse);
    expect(await repository.balance(), 0);
    await badBloc.close();
  });
}

/// A repository whose reads always throw — drives the generic error state.
class FailingKarmaRepository extends LocalKarmaRepository {
  FailingKarmaRepository()
      : super(store: _MemStore<KarmaEventRecord>((r) => r.eventId));

  @override
  Future<List<KarmaEvent>> events() async =>
      throw StateError('ledger unavailable');
}
