import 'dart:async';

import '../../audit/domain/audit_repository.dart';
import '../domain/audit_log_bloc.dart';
import '../domain/audit_log_state.dart';

/// Local implementation of [AuditLogBloc] (Task 11.2).
///
/// Backed by [AuditRepository] (in-memory for the harness,
/// SQLCipher for production). Monotonic sequence guards prevent stale
/// late-subscriber updates.
///
/// SECURITY CHECKPOINT (11.2):
/// - Repository failures map to a generic, payload-free
///   [AuditLogState] error — never leaking stack traces, database
///   errors, or PII.
/// - [refresh] reads only audit records and integrity status from the store.
class LocalAuditLogBloc implements AuditLogBloc {
  final AuditRepository _repository;

  final _controller = StreamController<AuditLogState>.broadcast();
  var _seq = 0;
  var _current = const AuditLogState();

  LocalAuditLogBloc({required AuditRepository repository})
      : _repository = repository;

  @override
  Stream<AuditLogState> get state => _controller.stream;

  @override
  AuditLogState get current => _current;

  @override
  Future<void> refresh() async {
    final seq = ++_seq;
    _emit(const AuditLogState(phase: AuditLogPhase.loading));

    try {
      final records = await _repository.getAll();
      final count = await _repository.getCount();

      if (seq != _seq) return; // stale

      _emit(AuditLogState(
        phase: AuditLogPhase.ready,
        records: records,
        recordCount: count,
        integrityValid: _current.integrityValid,
      ));
    } catch (_) {
      if (seq != _seq) return;
      _emit(const AuditLogState(
        phase: AuditLogPhase.error,
        errorMessage: 'Unable to load audit log',
      ));
    }
  }

  @override
  Future<void> verifyIntegrity() async {
    final seq = ++_seq;

    try {
      final valid = await _repository.verifyIntegrity();

      if (seq != _seq) return;

      _emit(AuditLogState(
        phase: AuditLogPhase.ready,
        records: _current.records,
        recordCount: _current.recordCount,
        integrityValid: valid,
      ));
    } catch (_) {
      if (seq != _seq) return;
      _emit(const AuditLogState(
        phase: AuditLogPhase.error,
        errorMessage: 'Unable to verify integrity',
      ));
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void _emit(AuditLogState state) {
    _current = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}
