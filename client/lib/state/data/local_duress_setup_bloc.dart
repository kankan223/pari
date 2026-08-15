import 'dart:async';

import '../../duress/domain/duress_service.dart';
import '../domain/duress_setup_bloc.dart';
import '../domain/duress_setup_state.dart';

/// [DuressSetupBloc] backed by the [DuressService] (data layer, Task 6.6).
///
/// Registers the real + duress PIN pair (both vaults initialized with
/// independent Argon2id derivation paths). Failures map to a generic
/// [DuressSetupPhase.failed] — the UI never learns whether the problem was
/// identical PINs, duplicate registration, or a storage error.
class LocalDuressSetupBloc implements DuressSetupBloc {
  final DuressService _service;

  // sync:true — emissions are delivered synchronously to listeners, so
  // register() callers (and tests) observe the new phase immediately after
  // the await completes (codebase convention, cf. LocalDevicePairingBloc).
  final StreamController<DuressSetupState> _controller =
      StreamController<DuressSetupState>.broadcast(sync: true);

  LocalDuressSetupBloc({required DuressService service}) : _service = service;

  @override
  Stream<DuressSetupState> get state => _controller.stream;

  @override
  Future<void> start() async {
    _controller.add(const DuressSetupState());
  }

  @override
  Future<void> register({
    required String realPin,
    required String duressPin,
  }) async {
    _controller.add(
      const DuressSetupState(phase: DuressSetupPhase.registering),
    );
    try {
      await _service.registerPins(realPin: realPin, duressPin: duressPin);
      _controller.add(
        const DuressSetupState(phase: DuressSetupPhase.registered),
      );
    } on DuressRegistrationException {
      _controller.add(
        const DuressSetupState(phase: DuressSetupPhase.failed, hasError: true),
      );
    } on ArgumentError {
      _controller.add(
        const DuressSetupState(phase: DuressSetupPhase.failed, hasError: true),
      );
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}
