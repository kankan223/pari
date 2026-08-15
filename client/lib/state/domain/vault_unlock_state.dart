/// Lifecycle phase of the vault unlock flow (Task 6.6).
enum VaultUnlockPhase {
  /// No PIN entered yet — the screen shows the PIN prompt.
  locked,

  /// A PIN was submitted and key derivation / decryption is in progress.
  unlocking,

  /// A vault was successfully opened. The routing decision (real vs decoy)
  /// is delivered through the [VaultUnlockBloc.unlock] RETURN VALUE, never
  /// through this state — so a late state listener can never observe which
  /// kind of vault was opened, and the unlock UI renders identically for
  /// the real and duress PINs.
  unlocked,

  /// The entered PIN could not open either vault. The presentation is a
  /// single GENERIC error — identical whether the PIN was empty, wrong, or
  /// "close to" the real or duress PIN (no side channel about which vault
  /// it almost matched).
  failed,
}

/// Immutable BLoC state for the vault unlock flow (Task 6.6).
///
/// SECURITY CHECKPOINT (Task 6.6): this state carries ONLY presentation
/// signals — no [Uint8List] key material, no [VaultDatabase] handle, no
/// real/duress indicator of any kind. The opened vault (database + key) is
/// returned directly by [VaultUnlockBloc.unlock] to the caller that routes
/// the UI, and is never persisted or logged. The screen renders IDENTICALLY
/// whether the real or the duress PIN was used — the only difference is
/// which vault the returned result points at.
class VaultUnlockState {
  final VaultUnlockPhase phase;

  /// True when both vaults have been registered (set by [start]). When
  /// false, the UI shows the setup path instead of the PIN prompt.
  final bool isRegistered;

  /// True when the last unlock attempt failed (generic presentation).
  final bool hasError;

  const VaultUnlockState({
    this.phase = VaultUnlockPhase.locked,
    this.isRegistered = false,
    this.hasError = false,
  });

  VaultUnlockState copyWith({
    VaultUnlockPhase? phase,
    bool? isRegistered,
    bool? hasError,
  }) =>
      VaultUnlockState(
        phase: phase ?? this.phase,
        isRegistered: isRegistered ?? this.isRegistered,
        hasError: hasError ?? this.hasError,
      );
}
