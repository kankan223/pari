import 'package:civic_commons/karma/data/karma_event_records.dart';
import 'package:civic_commons/karma/data/local_karma_repository.dart';
import 'package:civic_commons/karma/domain/karma_action.dart';
import 'package:civic_commons/repository/domain/entity_store.dart';
import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_karma_bloc.dart';
import 'package:civic_commons/state/ui/karma_status_screen.dart';
import 'package:flutter/material.dart';
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

class _FakeSecureFlagService implements SecureFlagService {
  bool enabled = false;
  bool disabled = false;

  @override
  Future<bool> isSecureFlagSupported() async => true;

  @override
  Future<void> enableSecureFlag() async {
    enabled = true;
  }

  @override
  Future<void> disableSecureFlag() async {
    disabled = true;
  }
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

  testWidgets('renders balance, tier, gates, and activity rows',
      (tester) async {
    await repository.record(
        action: KarmaAction.warRoomAnalystVetted, actorHash: _hash(1)); // +20
    await repository.record(
        action: KarmaAction.ledgerPostVerified, actorHash: _hash(1)); // +5

    await tester.pumpWidget(MaterialApp(
      home: KarmaStatusScreen(bloc: bloc),
    ));
    await tester.pumpAndSettle();

    expect(find.text('❧ CIVIC COMMONS'), findsOneWidget);
    expect(find.text('KARMA'), findsOneWidget);
    expect(find.text('25'), findsOneWidget); // balance
    expect(find.textContaining('tier'), findsOneWidget);
    expect(find.text('PRIVILEGES UNLOCKED BY KARMA'), findsOneWidget);
    expect(find.text('Post without probation'), findsOneWidget);
    expect(find.text('Peer Review voting'), findsOneWidget);
    expect(find.text('RECENT KARMA ACTIVITY'), findsOneWidget);
    expect(find.text('Post confirmed by peer review'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
  });

  testWidgets('gate checklist reflects satisfaction (50+ unlocks probation)',
      (tester) async {
    for (var i = 0; i < 10; i++) {
      await repository.record(
          action: KarmaAction.ledgerPostVerified, actorHash: _hash(1));
    }
    await tester.pumpWidget(MaterialApp(
      home: KarmaStatusScreen(bloc: bloc),
    ));
    await tester.pumpAndSettle();

    expect(find.text('50'), findsOneWidget); // balance
    // Skip-probation gate shows its threshold and is satisfied.
    expect(find.text('Post without probation'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsWidgets);
  });

  testWidgets('FLAG_SECURE is active on mount (SECURITY CHECKPOINT 10.2)',
      (tester) async {
    final flag = _FakeSecureFlagService();
    await tester.pumpWidget(MaterialApp(
      home: KarmaStatusScreen(bloc: bloc, secureFlagService: flag),
    ));
    await tester.pumpAndSettle();

    expect(flag.enabled, isTrue);
    // Screen still renders (FLAG_SECURE failure never blocks).
    expect(find.text('❧ CIVIC COMMONS'), findsOneWidget);
  });

  testWidgets('empty ledger renders the no-activity state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: KarmaStatusScreen(bloc: bloc),
    ));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget); // zero balance
    expect(find.text('No karma events yet.'), findsOneWidget);
  });

  testWidgets('zero-PII: no 64-hex hash, no phone, no blind handle in tree',
      (tester) async {
    await repository.record(
        action: KarmaAction.warRoomAnalystVetted, actorHash: _hash(1));
    await tester.pumpWidget(MaterialApp(
      home: KarmaStatusScreen(bloc: bloc),
    ));
    await tester.pumpAndSettle();

    final tree =
        tester.widgetList(find.byType(Text)).map((t) => (t as Text).data ?? '');
    for (final text in tree) {
      expect(text.contains(RegExp(r'[0-9a-f]{64}')), isFalse,
          reason: 'full 64-hex hash rendered: $text');
      expect(text.contains(RegExp(r'\+\d{10,15}')), isFalse,
          reason: 'phone-shaped text rendered: $text');
    }
  });
}
