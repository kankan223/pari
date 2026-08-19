import 'consent_record.dart';
import 'consent_type.dart';

/// Repository port for DPDP Consent (Task 11.1).
///
/// All operations are local-first and offline-safe. The repository
/// tracks consent records and supports data deletion on withdrawal.
///
/// SECURITY CHECKPOINT (11.1): the repository carries only
/// [ConsentRecord] objects with consent types and timestamps —
/// no identity, no PII, no tokens.
abstract class ConsentRepository {
  /// Returns the current consent record for [type], or null if never granted.
  Future<ConsentRecord?> getConsent(ConsentType type);

  /// Returns all consent records, newest first.
  Future<List<ConsentRecord>> getAllConsents();

  /// Returns true if consent is currently granted for [type].
  Future<bool> hasConsent(ConsentType type);

  /// Records a consent grant for [type] at [consentVersion].
  Future<void> grantConsent({
    required ConsentType type,
    required String consentVersion,
    required String textHash,
  });

  /// Records a consent withdrawal for [type].
  Future<void> withdrawConsent(ConsentType type);

  /// Returns true if all required consents are granted.
  /// Required consents: coreFunctionality, civicEngagement,
  /// securityContributions, educationalContent.
  Future<bool> hasAllRequiredConsents();

  /// Deletes all user data associated with the consent (data deletion
  /// on consent withdrawal per DPDP §8).
  Future<void> deleteUserData();

  /// Returns the current consent version string for display.
  String get currentConsentVersion;
}
