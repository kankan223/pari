import 'case_intake.dart';
import 'custody_log.dart';
import 'severity_scoring.dart';
import 'war_room_case.dart';

/// Repository port for War Room cases (Task 8.1).
///
/// The UI layer reads case data ONLY through this port (clean architecture
/// — no repository/network access from widgets). The offline-first contract
/// applies: the list renders from the local case store; a persisted store
/// lands with the 8.x data tasks.
///
/// SECURITY CHECKPOINT (Task 8.1): every method returns/accepts ONLY the
/// non-PII [WarRoomCase] projection — case numbers, severity, timestamps,
/// counts. No raw payloads cross this boundary.
abstract class WarCaseRepository {
  /// All cases, newest filed first (the victim's own case list).
  Future<List<WarRoomCase>> listCases();

  /// A single case by its stamp number, or null.
  Future<WarRoomCase?> getCaseById(String caseNumber);

  /// Files a new case from the completed intake submission, assigning the
  /// next sequential dossier stamp number (`CC-0047`). Returns the filed
  /// case.
  Future<WarRoomCase> fileCase(CaseIntakeSubmission submission);

  /// One-tap pause/unpause (PRD §7.3-4).
  Future<WarRoomCase> setPaused(String caseNumber, bool paused);

  /// One-tap withdraw (PRD §7.3-4) — moves the case to withdrawn.
  Future<WarRoomCase> withdraw(String caseNumber);

  /// Human-reviewed severity override (Task 8.4): re-bands [caseNumber] to
  /// [override].newSeverity, updates the SLA projection, and records the
  /// override (with reason + timestamp) on the case. Returns the updated case.
  Future<WarRoomCase> overrideSeverity(
    String caseNumber,
    SeverityOverride override,
  );

  /// Posts a blinded analyst update (Task 8.5 blind-review contract): the
  /// note is attributed ONLY via the author's blinded [analystId] handle.
  /// Only an analyst assigned to the case may post (enforced). Returns the
  /// updated case.
  Future<WarRoomCase> addAnalystUpdate(
    String caseNumber,
    String analystId,
    String text,
    String progress,
  );

  /// The case's append-only custody chain (Task 8.6), oldest first.
  Future<List<CustodyEvent>> custodyEvents(String caseNumber);

  /// True when every custody chain in the log recomputes exactly — the
  /// immutability checkpoint (Task 8.6).
  Future<bool> verifyCustodyIntegrity();

  /// Signs the case's Verified Intel Report (Task 8.6) and records a
  /// REPORT SIGNED custody event. Returns the signed report.
  Future<SignedReport> signVerifiedReport(String caseNumber);

  /// Queues a legal-aid handoff for the case (Task 8.6) and records a
  /// LEGAL-AID HANDOFF QUEUED custody event. Returns the handoff id.
  Future<String> queueLegalAidHandoff(String caseNumber);
}
