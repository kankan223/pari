import 'dart:typed_data';

import 'package:civic_commons/transparency/data/in_memory_transparency_repository.dart';
import 'package:civic_commons/transparency/domain/transparency_action.dart';
import 'package:civic_commons/transparency/domain/transparency_record.dart';
import 'package:civic_commons/transparency/domain/transparency_repository.dart';
import 'package:civic_commons/state/data/local_transparency_log_bloc.dart';
import 'package:civic_commons/state/domain/transparency_log_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTransparencyRepository repo;
  late LocalTransparencyLogBloc bloc;

  late _TestHasher hasher;

  setUp(() {
    hasher = _TestHasher();
    repo = InMemoryTransparencyRepository(hasher: hasher);
    bloc = LocalTransparencyLogBloc(
      repository: repo,
      pinCode: '800001',
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  test('initial state is idle', () {
    expect(bloc.current.phase, TransparencyLogPhase.idle);
  });

  test('refresh transitions to ready with records', () async {
    await repo.append(await _testRecord(
      seq: 0,
      summary: 'System started',
    ));

    await bloc.refresh();
    expect(bloc.current.phase, TransparencyLogPhase.ready);
    expect(bloc.current.records.length, 1);
    expect(bloc.current.recordCount, 1);
  });

  test('verifyIntegrity updates integrity status', () async {
    await repo.append(await _testRecord(
      seq: 0,
      summary: 'System started',
    ));
    await bloc.refresh();

    // The no-op hasher accepts any hash, so integrity is valid.
    expect(bloc.current.integrityValid, true);
    await bloc.verifyIntegrity();
    expect(bloc.current.integrityValid, true);
  });

  test('repository failure maps to error state', () async {
    final failingBloc = LocalTransparencyLogBloc(
      repository: _FailingTransparencyRepo(),
      pinCode: '800001',
    );
    await failingBloc.refresh();
    expect(failingBloc.current.phase, TransparencyLogPhase.error);
    await failingBloc.close();
  });

  test('state stream emits updates', () async {
    final states = <TransparencyLogState>[];
    final sub = bloc.state.listen(states.add);

    await bloc.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(states.length, 2); // loading + ready
    expect(states[0].phase, TransparencyLogPhase.loading);
    expect(states[1].phase, TransparencyLogPhase.ready);

    await sub.cancel();
  });

  test('isolates by pinCode', () async {
    // Record for a different pinCode.
    await repo.append(await _testRecord(
      seq: 0,
      summary: 'Other pin',
      pinCode: '999999',
    ));

    await bloc.refresh();
    expect(bloc.current.records.length, 0);
  });
}

Future<TransparencyRecord> _testRecord({
  required int seq,
  required String summary,
  String? pinCode,
}) async {
  final hasher = _TestHasher();
  final record = TransparencyRecord(
    seq: seq,
    recordId: 'rec-${seq.toString().padLeft(3, '0')}',
    action: TransparencyAction.systemEvent,
    summary: summary,
    pinCode: pinCode ?? '800001',
    occurredAt: DateTime.utc(2026, 8, 18, 10 + seq),
    prevHash: TransparencyRecord.genesisHash,
    selfHash: '',
  );
  final selfHash = await record.computeSelfHash(hasher);
  return TransparencyRecord(
    seq: record.seq,
    recordId: record.recordId,
    action: record.action,
    summary: record.summary,
    pinCode: record.pinCode,
    occurredAt: record.occurredAt,
    prevHash: record.prevHash,
    selfHash: selfHash,
  );
}

class _TestHasher implements TransparencyHasher {
  @override
  Future<Uint8List> hash(List<int> bytes) async {
    return Uint8List.fromList(List.generate(32, (i) => bytes.length % 256));
  }
}

class _FailingTransparencyRepo implements TransparencyRepository {
  @override
  Future<List<TransparencyRecord>> getByPinCode(String pinCode) async =>
      throw Exception('db down');

  @override
  Future<int> getCount(String pinCode) async => throw Exception('db down');

  @override
  Future<void> append(TransparencyRecord record) async =>
      throw Exception('db down');

  @override
  Future<bool> verifyIntegrity(String pinCode) async =>
      throw Exception('db down');
}
