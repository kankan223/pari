import 'dart:async';

import '../../transparency/domain/transparency_repository.dart';
import '../domain/transparency_log_bloc.dart';
import '../domain/transparency_log_state.dart';

/// Local implementation of [TransparencyLogBloc] (Task 10.5).
///
/// Backed by [TransparencyRepository] (in-memory for the harness,
/// SQLCipher for production). Monotonic sequence guards prevent stale
/// late-subscriber updates.
///
/// SECURITY CHECKPOINT (10.5):
/// - Repository failures map to a generic, payload-free
///   [TransparencyLogState] error — never leaking stack traces,
///   database errors, or PII.
/// - [refresh] reads only public-label transparency records from the store.
class LocalTransparencyLogBloc implements TransparencyLogBloc {
  final TransparencyRepository _repository;
  final String _pinCode;

  final _controller = StreamController<TransparencyLogState>.broadcast();
  var _seq = 0;
  var _current = const TransparencyLogState();

  LocalTransparencyLogBloc({
    required TransparencyRepository repository,
    required String pinCode,
  })  : _repository = repository,
        _pinCode = pinCode;

  @override
  Stream<TransparencyLogState> get state => _controller.stream;

  @override
  TransparencyLogState get current => _current;

  @override
  Future<void> refresh() async {
    final seq = ++_seq;
    _emit(const TransparencyLogState(phase: TransparencyLogPhase.loading));

    try {
      final records = await _repository.getByPinCode(_pinCode);
      final count = await _repository.getCount(_pinCode);
      final valid = await _repository.verifyIntegrity(_pinCode);

      if (seq != _seq) return; // stale

      _emit(TransparencyLogState(
        phase: TransparencyLogPhase.ready,
        records: records,
        integrityValid: valid,
        recordCount: count,
      ));
    } catch (_) {
      if (seq != _seq) return;
      _emit(const TransparencyLogState(
        phase: TransparencyLogPhase.error,
        errorMessage: 'Unable to load transparency log',
      ));
    }
  }

  @override
  Future<void> verifyIntegrity() async {
    try {
      final valid = await _repository.verifyIntegrity(_pinCode);
      if (_current.phase == TransparencyLogPhase.ready) {
        _emit(TransparencyLogState(
          phase: _current.phase,
          records: _current.records,
          integrityValid: valid,
          recordCount: _current.recordCount,
        ));
      }
    } catch (_) {
      // Integrity check failure → refresh will show error.
      await refresh();
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void _emit(TransparencyLogState state) {
    _current = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}
