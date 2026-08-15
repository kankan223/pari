/// Lifecycle phase of the duress PIN setup flow (Task 6.6 onboarding).
enum DuressSetupPhase {
  /// Not started.
  idle,

  /// PINs are being derived and both vaults initialized.
  registering,

  /// Both PINs were registered successfully.
  registered,

  /// Registration failed (identical PINs, already registered, or a storage
  /// error). The UI shows a generic message — no reason-specific detail.
  failed,
}

/// Immutable BLoC state for the duress PIN setup flow (Task 6.6).
///
/// SECURITY CHECKPOINT (Task 6.6): this state never carries the PINs, any
/// derived key material, or any indication of which PIN is "real" — the
/// setup screen itself labels the fields (the user is choosing them), but
/// the state and the persisted vaults never do.
class DuressSetupState {
  final DuressSetupPhase phase;

  /// True when the last registration attempt failed (generic presentation).
  final bool hasError;

  const DuressSetupState({
    this.phase = DuressSetupPhase.idle,
    this.hasError = false,
  });

  DuressSetupState copyWith({
    DuressSetupPhase? phase,
    bool? hasError,
  }) =>
      DuressSetupState(
        phase: phase ?? this.phase,
        hasError: hasError ?? this.hasError,
      );
}
