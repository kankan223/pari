import 'dart:async';

import '../../duress/domain/duress_service.dart';
import '../domain/vault_unlock_bloc.dart';
import '../domain/vault_unlock_state.dart';

/// [VaultUnlockBloc] backed by the [DuressService] (data layer, Task 6.6).
///
/// Delegates unlock selection to the duress service (pure decryption-based
/// selection — the service never stores which PIN is real vs duress) and
/// exposes only presentation state on the stream. The opened vault is
/// returned from [unlock] so the composition root routes real-vs-decoy UI.
class LocalVaultUnlockBloc implements VaultUnlockBloc {
  final DuressService _service;

  // sync:true — emissions are delivered synchronously to listeners, so
  // unlock() callers (and tests) observe the new phase immediately after
  // the await completes (codebase convention, cf. LocalDevicePairingBloc).
  final StreamController<VaultUnlockState> _controller =
      StreamController<VaultUnlockState>.broadcast(sync: true);

  /// Registration state learned at [start] — carried forward on EVERY
  /// emission so a failed unlock cannot flip the UI back to the setup prompt.
  bool _isRegistered = false;

  LocalVaultUnlockBloc({required DuressService service}) : _service = service;

  @override
  Stream<VaultUnlockState> get state => _controller.stream;

  @override
  Future<void> start() async {
    _isRegistered = await _service.isRegistered();
    _controller.add(
      VaultUnlockState(
        phase: VaultUnlockPhase.locked,
        isRegistered: _isRegistered,
      ),
    );
  }

  @override
  Future<UnlockResult?> unlock(String pin) async {
    _controller.add(
      VaultUnlockState(
        phase: VaultUnlockPhase.unlocking,
        isRegistered: _isRegistered,
      ),
    );
    try {
      final result = await _service.unlock(pin);
      _controller.add(
        VaultUnlockState(
          phase: VaultUnlockPhase.unlocked,
          isRegistered: _isRegistered,
        ),
      );
      return result;
    } on DuressPinException {
      // Generic failure — identical for a wrong PIN, an empty PIN, or a PIN
      // that nearly matched either vault. No side channel.
      _controller.add(
        VaultUnlockState(
          phase: VaultUnlockPhase.failed,
          hasError: true,
          isRegistered: _isRegistered,
        ),
      );
      return null;
    } on ArgumentError {
      // Empty PIN — same generic presentation as any other failure.
      _controller.add(
        VaultUnlockState(
          phase: VaultUnlockPhase.failed,
          hasError: true,
          isRegistered: _isRegistered,
        ),
      );
      return null;
    } catch (_) {
      // A storage/channel failure must never crash the unlock UI and must
      // never leak detail — same generic failure as a wrong PIN.
      _controller.add(
        VaultUnlockState(
          phase: VaultUnlockPhase.failed,
          hasError: true,
          isRegistered: _isRegistered,
        ),
      );
      return null;
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}
