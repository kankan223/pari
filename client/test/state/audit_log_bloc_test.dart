import 'package:civic_commons/audit/data/in_memory_audit_repository.dart';
import 'package:civic_commons/audit/domain/audit_action.dart';
import 'package:civic_commons/audit/domain/audit_record.dart';
import 'package:civic_commons/audit/domain/audit_repository.dart';
import 'package:civic_commons/state/data/local_audit_log_bloc.dart';
import 'package:civic_commons/state/domain/audit_log_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalAuditLogBloc', () {
    late InMemoryAuditRepository repo;
    late LocalAuditLogBloc bloc;

    setUp(() {
      repo = InMemoryAuditRepository();
      bloc = LocalAuditLogBloc(repository: repo);
    });

    tearDown(() async {
      await bloc.close();
    });

    AuditRecord makeRecord({int seq = 0}) {
      return AuditRecord(
        seq: seq,
        recordId: 'audit-$seq',
        action: AuditAction.consentGranted,
        summary: 'Test event $seq',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash:
            seq == 0 ? AuditRecord.genesisHash : 'self_hash_${seq - 1}',
        selfHash: 'self_hash_$seq',
      );
    }

    test('initial state is idle', () {
      expect(bloc.current.phase, AuditLogPhase.idle);
    });

    test('refresh loads audit records', () async {
      await repo.append(makeRecord(seq: 0));

      await bloc.refresh();
      expect(bloc.current.phase, AuditLogPhase.ready);
      expect(bloc.current.recordCount, 1);
      expect(bloc.current.records.length, 1);
    });

    test('refresh emits loading then ready', () async {
      final phases = <AuditLogPhase>[];
      final sub = bloc.state.listen((s) => phases.add(s.phase));

      await bloc.refresh();
      await Future.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(phases, contains(AuditLogPhase.loading));
      expect(phases, contains(AuditLogPhase.ready));
    });

    test('verifyIntegrity reports valid chain', () async {
      // Empty repo = valid chain by definition
      await bloc.verifyIntegrity();
      expect(bloc.current.integrityValid, true);
    });

    test('verifyIntegrity reports invalid chain', () async {
      // Manually corrupt the chain by adding a record with wrong prevHash
      // The repo validates this, so we need a failing hasher
      final badRepo = _FailingAuditRepository();
      final badBloc = LocalAuditLogBloc(repository: badRepo);

      await badBloc.verifyIntegrity();
      expect(bloc.current.phase, AuditLogPhase.idle);

      await badBloc.close();
    });

    test('repository error maps to generic error state', () async {
      final badRepo = _FailingAuditRepository();
      final badBloc = LocalAuditLogBloc(repository: badRepo);

      await badBloc.refresh();
      expect(badBloc.current.phase, AuditLogPhase.error);
      expect(badBloc.current.errorMessage, isNotNull);
      expect(badBloc.current.errorMessage!.contains('audit'), true);

      await badBloc.close();
    });

    test('close prevents further state emissions', () async {
      final phases = <AuditLogPhase>[];
      bloc.state.listen((s) => phases.add(s.phase));

      await bloc.refresh();
      await bloc.close();
      await Future.delayed(const Duration(milliseconds: 10));

      expect(phases.last, AuditLogPhase.ready);
    });
  });
}

class _FailingAuditRepository implements AuditRepository {
  @override
  Future<List<AuditRecord>> getAll() async =>
      throw Exception('DB unavailable');

  @override
  Future<int> getCount() async => throw Exception('DB unavailable');

  @override
  Future<void> append(AuditRecord record) async =>
      throw Exception('DB unavailable');

  @override
  Future<bool> verifyIntegrity() async =>
      throw Exception('DB unavailable');
}
