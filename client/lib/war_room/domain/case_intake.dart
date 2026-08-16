import '../../pii/domain/pii_redaction.dart';
import 'case_severity.dart';

/// Situation categories for the intake Step 1 (DESIGN.md §8.3) — fixed,
/// non-sensitive labels.
enum IntakeSituation {
  blackmailExtortion(
    label: 'I am being blackmailed or extorted',
    baseSeverity: CaseSeverity.high,
  ),
  intimateImageThreat(
    label: 'Someone is threatening to share intimate images',
    baseSeverity: CaseSeverity.high,
  ),
  fakeProfile(
    label: 'I found a fake profile using my identity',
    baseSeverity: CaseSeverity.medium,
  ),
  threateningMessages(
    label: 'I received threatening or abusive messages',
    baseSeverity: CaseSeverity.medium,
  ),
  tracingHarasser(
    label: 'I need help tracing who is harassing me',
    baseSeverity: CaseSeverity.low,
  ),
  somethingElse(
    label: 'Something else',
    baseSeverity: CaseSeverity.medium,
  );

  const IntakeSituation({
    required this.label,
    required this.baseSeverity,
  });

  /// The victim-facing radio label.
  final String label;

  /// Situation-category severity floor (a pure constant, never user-input).
  final CaseSeverity baseSeverity;
}

/// Urgency selection for intake Step 4 (DESIGN.md §8.3).
enum IntakeUrgency {
  immediate(
    label: 'There is an immediate threat or deadline (< 24 hrs)',
    floorSeverity: CaseSeverity.critical,
  ),
  thisWeek(
    label: 'This needs attention soon (this week)',
    floorSeverity: CaseSeverity.medium,
  ),
  noDeadline(
    label: 'No immediate deadline — take the time needed',
    floorSeverity: CaseSeverity.low,
  );

  const IntakeUrgency({
    required this.label,
    required this.floorSeverity,
  });

  /// The radio label.
  final String label;

  /// Urgency severity floor — an immediate threat can never be filed LOW.
  final CaseSeverity floorSeverity;
}

/// The completed trauma-aware intake submission (DESIGN.md §8.3, 5 steps).
///
/// SECURITY CHECKPOINT (Task 8.1): [narrative] is case CONTENT (it becomes
/// the encrypted case payload in Task 8.2) — never identity. The intake
/// form collects no phone, no name, no hash, no handle.
class CaseIntakeSubmission {
  final IntakeSituation situation;
  final String narrative;

  /// Evidence attachments arrive in Task 8.2 (encrypted upload) — the
  /// foundation keeps the count only.
  final int evidenceCount;

  /// The intake session's local draft id — DEK-encrypted evidence attaches
  /// to it in Step 3 BEFORE the case is filed (Task 8.2). Server-side
  /// reconciliation (draft → real stamp) is a backend concern.
  final String draftCaseId;

  /// PII redaction outcome for [narrative] (Task 8.3). Null when the intake
  /// ran without a redaction pipeline (foundation/dev); when non-null the
  /// narrative in [narrative] is the REDACTED text and [redactionApplied]
  /// is true. Carries only non-PII aggregate counts.
  final PiiRedactionReport? redactionReport;

  /// True once the narrative has been scrubbed by the local redaction
  /// pipeline (Task 8.3) — the case payload then contains zero raw PII.
  final bool redactionApplied;

  final IntakeUrgency urgency;

  /// Consent checkboxes (Step 5). The first two are REQUIRED; the third is
  /// the optional anonymized-Ledger-publish opt-in.
  final bool consentNotLegalAdvice;
  final bool consentLegalAidReferral;
  final bool optInAnonymizedLedger;

  const CaseIntakeSubmission({
    required this.situation,
    required this.narrative,
    required this.urgency,
    required this.consentNotLegalAdvice,
    required this.consentLegalAidReferral,
    this.evidenceCount = 0,
    this.draftCaseId = '',
    this.optInAnonymizedLedger = false,
    this.redactionReport,
    this.redactionApplied = false,
  });

  /// True when the two REQUIRED consents are checked (Step 5 gate).
  bool get consentComplete => consentNotLegalAdvice && consentLegalAidReferral;

  /// The deterministic PROVISIONAL severity (DESIGN.md §8.3 Step 4 →
  /// severity): the higher of the situation-category severity and the
  /// urgency floor. Never downgrades a serious category.
  ///
  /// NOTE (Task 8.1 foundation): this is a provisional triage hint. The
  /// keyword-based deterministic severity scoring engine replaces it at
  /// triage in Task 8.4.
  CaseSeverity get provisionalSeverity => CaseSeverity.maxSeverity(
        situation.baseSeverity,
        urgency.floorSeverity,
      );
}
