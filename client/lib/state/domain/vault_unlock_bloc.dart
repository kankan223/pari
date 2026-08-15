import '../../duress/domain/duress_service.dart';
import 'vault_unlock_state.dart';

/// BLoC for the vault unlock flow (Task 6.6).
///
/// Exposes a stream of [VaultUnlockState] for the PIN prompt UI. The
/// opened vault (real or decoy) is returned from [unlock] so the caller
/// (composition root) can route to the appropriate UI — the state stream
/// itself never reveals which kind of vault was opened, and never carries
/// the database handle or key material.
///
/// SECURITY CHECKPOINT (Task 6.6): the duress PIN is indistinguishable
/// from the real PIN — the same [unlock] method is used for both, the
/// state transitions are identical, and only the RETURN VALUE differs
/// (real vault vs decoy vault). Nothing here persists which PIN is real.
abstract class VaultUnlockBloc {
  /// Stream of unlock states (locked → unlocking → unlocked/failed).
  Stream<VaultUnlockState> get state;

  /// Loads registration state and emits the initial [VaultUnlockState].
  Future<void> start();

  /// Attempts to unlock a vault with [pin].
  ///
  /// Returns the opened [UnlockResult] (real or decoy database + key) on
  /// success, or null when the PIN cannot open either vault. The result is
  /// in-memory only — the caller must use it to route the UI and must
  /// never persist or log it.
  Future<UnlockResult?> unlock(String pin);

  /// Releases resources.
  Future<void> close();
}
