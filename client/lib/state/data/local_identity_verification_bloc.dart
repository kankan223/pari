import 'dart:async';

import '../../identity/pillar_claim_sources.dart';
import '../../identity/unified_identity_service.dart';
import '../domain/identity_verification_bloc.dart';
import '../domain/identity_verification_state.dart';

/// [UnifiedIdentityService]-backed [IdentityVerificationBloc] (data layer,
/// Task 10.1).
///
/// Runs the verification through the injected service; composes the
/// per-pillar minimum claims via [composeAllClaims] on success. Failures
/// degrade to the GENERIC error state — never a payload, never internal
/// detail (a source outage must not crash onboarding).
class LocalIdentityVerificationBloc implements IdentityVerificationBloc {
  final UnifiedIdentityService _service;
  final PillarClaimSources _sources;
  final StreamController<IdentityVerificationState> _controller =
      StreamController<IdentityVerificationState>.broadcast();
  IdentityVerificationState _current = const IdentityVerificationState.idle();
  int _seq = 0;
  bool _closed = false;

  LocalIdentityVerificationBloc({
    required UnifiedIdentityService service,
    required PillarClaimSources sources,
  })  : _service = service,
        _sources = sources;

  @override
  Stream<IdentityVerificationState> get state => _controller.stream;

  @override
  IdentityVerificationState get current => _current;

  @override
  Future<void> verify() async {
    if (_closed) {
      return;
    }
    final seq = ++_seq;
    _emit(const IdentityVerificationState.loading());
    try {
      final blindHashId = await _service.blindHashId();
      if (_closed || seq != _seq) {
        return; // stale — a newer verify() superseded this one.
      }
      if (blindHashId == null) {
        _emit(const IdentityVerificationState.noIdentity());
        return;
      }
      final claims = await composeAllClaims(
        blindHashId: blindHashId,
        sources: _sources,
      );
      if (_closed || seq != _seq) {
        return;
      }
      _emit(IdentityVerificationState.verified(
        blindHashId: blindHashId,
        pillarClaims: claims,
      ));
    } catch (_) {
      if (_closed || seq != _seq) {
        return;
      }
      // Deliberately payload-free: a source failure never surfaces PII or
      // internal detail in state.
      _emit(const IdentityVerificationState.error(
          'Could not verify your identity. Please try again.'));
    }
  }

  void _emit(IdentityVerificationState state) {
    _current = state;
    _controller.add(state);
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _controller.close();
  }
}
