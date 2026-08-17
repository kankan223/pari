import '../../identity/civic_pillar.dart';
import '../../identity/pillar_claims.dart';

/// Verification phase of the unified identity onboarding flow (Task 10.1).
enum IdentityVerificationPhase {
  /// Not started.
  idle,

  /// Reading the local identity + composing the per-pillar claims.
  loading,

  /// The device has a shared identity and the per-pillar claims are composed.
  verified,

  /// The device has NO identity yet — the onboarding phone flow must run.
  noIdentity,

  /// A local source failed — generic, payload-free error.
  error,
}

/// Immutable BLoC state for the identity verification screen (Task 10.1).
///
/// SECURITY CHECKPOINT (Task 10.1): the state carries ONLY the shared blind
/// hash (one-way, never rendered in full), the blinded [displayHandle], and
/// the per-pillar MINIMUM claims projections. No phone number, no username
/// outside the Vault's claim, no full profile ever appears in state.
class IdentityVerificationState {
  final IdentityVerificationPhase phase;

  /// The shared blind hash (read-only identity, available to every pillar).
  final String? blindHashId;

  /// The per-pillar minimum claims projections (verified phase).
  final Map<CivicPillar, PillarClaims> pillarClaims;

  /// GENERIC error message — never a payload, never internal detail.
  final String? errorMessage;

  const IdentityVerificationState({
    this.phase = IdentityVerificationPhase.idle,
    this.blindHashId,
    this.pillarClaims = const {},
    this.errorMessage,
  });

  const IdentityVerificationState.idle() : this();

  const IdentityVerificationState.loading()
      : this(phase: IdentityVerificationPhase.loading);

  const IdentityVerificationState.verified({
    required this.blindHashId,
    required this.pillarClaims,
  })  : phase = IdentityVerificationPhase.verified,
        errorMessage = null;

  const IdentityVerificationState.noIdentity()
      : this(phase: IdentityVerificationPhase.noIdentity);

  const IdentityVerificationState.error(String this.errorMessage)
      : phase = IdentityVerificationPhase.error,
        blindHashId = null,
        pillarClaims = const {};

  bool get isIdle => phase == IdentityVerificationPhase.idle;
  bool get isLoading => phase == IdentityVerificationPhase.loading;
  bool get isVerified => phase == IdentityVerificationPhase.verified;
  bool get isNoIdentity => phase == IdentityVerificationPhase.noIdentity;
  bool get isError => phase == IdentityVerificationPhase.error;

  /// The blinded non-PII display handle (`@citizen_` + 6 hex).
  String get displayHandle => blindHashId == null
      ? ''
      : PillarClaims.compose(
          pillar: CivicPillar.vault,
          blindHashId: blindHashId!,
        ).displayHandle;
}
