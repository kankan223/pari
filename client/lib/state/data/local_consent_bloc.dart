import 'dart:async';

import '../../consent/domain/consent_repository.dart';
import '../../consent/domain/consent_type.dart';
import '../domain/consent_bloc.dart';
import '../domain/consent_state.dart';

/// Local implementation of [ConsentBloc] (Task 11.1).
///
/// Backed by [ConsentRepository] (in-memory for the harness,
/// SQLCipher for production). Monotonic sequence guards prevent stale
/// late-subscriber updates.
///
/// SECURITY CHECKPOINT (11.1):
/// - Repository failures map to a generic, payload-free
///   [ConsentState] error — never leaking stack traces, database
///   errors, or PII.
/// - [refresh] reads only consent types and boolean flags from the store.
class LocalConsentBloc implements ConsentBloc {
  final ConsentRepository _repository;

  final _controller = StreamController<ConsentState>.broadcast();
  var _seq = 0;
  var _current = const ConsentState();

  LocalConsentBloc({required ConsentRepository repository})
      : _repository = repository;

  @override
  Stream<ConsentState> get state => _controller.stream;

  @override
  ConsentState get current => _current;

  @override
  Future<void> refresh() async {
    final seq = ++_seq;
    _emit(const ConsentState(phase: ConsentPhase.loading));

    try {
      final consentStatus = <ConsentType, bool>{};
      for (final type in ConsentType.values) {
        consentStatus[type] = await _repository.hasConsent(type);
      }
      final allRequired = await _repository.hasAllRequiredConsents();
      final version = _repository.currentConsentVersion;

      if (seq != _seq) return; // stale

      _emit(ConsentState(
        phase: ConsentPhase.ready,
        consentStatus: consentStatus,
        allRequiredGranted: allRequired,
        consentVersion: version,
      ));
    } catch (_) {
      if (seq != _seq) return;
      _emit(const ConsentState(
        phase: ConsentPhase.error,
        errorMessage: 'Unable to load consent status',
      ));
    }
  }

  @override
  Future<void> grantAll() async {
    final seq = ++_seq;
    _emit(const ConsentState(phase: ConsentPhase.loading));

    try {
      final version = _repository.currentConsentVersion;
      final textHash = 'consent_v${version}_hash';

      for (final type in ConsentType.values) {
        await _repository.grantConsent(
          type: type,
          consentVersion: version,
          textHash: textHash,
        );
      }

      if (seq != _seq) return;
      await refresh();
    } catch (_) {
      if (seq != _seq) return;
      _emit(const ConsentState(
        phase: ConsentPhase.error,
        errorMessage: 'Unable to grant consent',
      ));
    }
  }

  @override
  Future<void> withdrawAll() async {
    final seq = ++_seq;
    _emit(const ConsentState(phase: ConsentPhase.loading));

    try {
      for (final type in ConsentType.values) {
        await _repository.withdrawConsent(type);
      }

      if (seq != _seq) return;

      _emit(ConsentState(
        phase: ConsentPhase.ready,
        consentStatus: {for (final t in ConsentType.values) t: false},
        allRequiredGranted: false,
        consentVersion: _repository.currentConsentVersion,
      ));
    } catch (_) {
      if (seq != _seq) return;
      _emit(const ConsentState(
        phase: ConsentPhase.error,
        errorMessage: 'Unable to withdraw consent',
      ));
    }
  }

  @override
  Future<void> withdrawConsent(ConsentType type) async {
    final seq = ++_seq;

    try {
      await _repository.withdrawConsent(type);
      if (seq != _seq) return;
      await refresh();
    } catch (_) {
      if (seq != _seq) return;
      _emit(const ConsentState(
        phase: ConsentPhase.error,
        errorMessage: 'Unable to withdraw consent',
      ));
    }
  }

  @override
  Future<void> deleteData() async {
    final seq = ++_seq;
    _emit(const ConsentState(phase: ConsentPhase.deleting));

    try {
      await _repository.deleteUserData();

      if (seq != _seq) return;

      _emit(ConsentState(
        phase: ConsentPhase.deleted,
        consentStatus: {for (final t in ConsentType.values) t: false},
        allRequiredGranted: false,
        consentVersion: _repository.currentConsentVersion,
      ));
    } catch (_) {
      if (seq != _seq) return;
      _emit(const ConsentState(
        phase: ConsentPhase.error,
        errorMessage: 'Unable to delete user data',
      ));
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void _emit(ConsentState state) {
    _current = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}
