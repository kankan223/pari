import 'identity_verification_state.dart';

/// BLoC for the unified identity verification flow (Task 10.1 — one-time
/// during onboarding).
///
/// The UI binds to [state] and calls [verify] — it never talks to the
/// identity service or claim sources directly.
///
/// SECURITY CHECKPOINT (Task 10.1): [IdentityVerificationState] carries only
/// the shared blind hash + per-pillar minimum claims (blinded handle for
/// display). A phone number, a username outside the Vault claim, or a full
/// profile can never appear in state; error states carry no payload at all.
abstract class IdentityVerificationBloc {
  /// Stream of verification states (idle → loading → verified | noIdentity |
  /// error).
  Stream<IdentityVerificationState> get state;

  /// Runs the verification: reads the local identity and composes the
  /// per-pillar minimum claims.
  Future<void> verify();

  /// The current state (for late subscribers).
  IdentityVerificationState get current;

  /// Releases resources.
  Future<void> close();
}
