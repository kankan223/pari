import '../../consent/domain/consent_type.dart';

/// DPDP consent phases (Task 11.1).
enum ConsentPhase {
  /// Not started.
  idle,

  /// Checking existing consent status.
  loading,

  /// Consent status is known — user can grant or withdraw.
  ready,

  /// A local source failed — generic, payload-free error.
  error,

  /// Data deletion is in progress (on consent withdrawal).
  deleting,

  /// Data deletion complete — user must re-consent.
  deleted,
}

/// Immutable state projection for DPDP Consent (Task 11.1).
///
/// Carries the consent status for each type, whether all required
/// consents are granted, and the current consent version.
///
/// SECURITY CHECKPOINT (11.1): the state carries only boolean consent
/// flags and fixed type labels — no phone numbers, no blind hashes,
/// no identity fields.
class ConsentState {
  final ConsentPhase phase;
  final Map<ConsentType, bool> consentStatus;
  final bool allRequiredGranted;
  final String consentVersion;
  final String? errorMessage;

  const ConsentState({
    this.phase = ConsentPhase.idle,
    this.consentStatus = const {},
    this.allRequiredGranted = false,
    this.consentVersion = '1.0',
    this.errorMessage,
  });

  /// Convenience: is [type] currently granted?
  bool hasConsent(ConsentType type) => consentStatus[type] ?? false;
}
