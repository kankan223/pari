import '../../war_room/domain/case_intake.dart';
import '../../war_room/domain/custody_log.dart';
import '../../war_room/domain/evidence_item.dart';
import '../../war_room/domain/severity_scoring.dart';
import 'war_room_state.dart';

/// BLoC for the War Room (Task 8.1/8.2).
///
/// Exposes a stream of [WarRoomState] derived from the local case
/// repository (local-first — no network in the read path). The UI binds to
/// [state] and never talks to the repository or network directly.
///
/// SECURITY CHECKPOINT (Task 8.1): state carries only UI-safe
/// [WarRoomCaseSummary]s — dossier stamp attributes, never identity.
abstract class WarRoomBloc {
  /// Stream of War Room states.
  Stream<WarRoomState> get state;

  /// Loads the case list from the local store.
  Future<void> start();

  /// Re-reads the local case store.
  Future<void> refresh();

  /// Opens a case detail by stamp number (null clears the selection).
  Future<void> openCase(String caseNumber);

  /// Clears the selected case detail.
  Future<void> closeCase();

  /// Files a new case from the completed intake submission. Returns the
  /// assigned dossier stamp number (e.g. `CC-0048`).
  Future<String> fileCase(CaseIntakeSubmission submission);

  /// One-tap pause/unpause (PRD §7.3-4).
  Future<void> setPaused(String caseNumber, bool paused);

  /// One-tap withdraw (PRD §7.3-4).
  Future<void> withdraw(String caseNumber);

  /// Attaches DEK-encrypted evidence to the intake draft [draftCaseId]
  /// (Task 8.2). The file bytes are sealed + the DEK wrapped + the sealed
  /// envelope queued BEFORE the UI hears back; the state emits the new
  /// [EvidenceSummary] on success and a GENERIC error on failure (never a
  /// crash, never a stack trace). Returns the evidence id.
  Future<String> attachEvidence(String draftCaseId, PickedEvidence evidence);

  /// Reloads locally persisted evidence into the state (cold-start recovery).
  Future<void> refreshEvidence();

  /// Human-reviewed severity override (Task 8.4): re-bands the case to
  /// [override].newSeverity with the analyst's reason. The emitted state
  /// reflects the new band + SLA; the original triage stays for audit.
  Future<void> overrideSeverity(String caseNumber, SeverityOverride override);

  /// Posts a blinded analyst update (Task 8.5): attributed ONLY via the
  /// author's blinded [analystId] handle; only an analyst assigned to the
  /// case may post. The emitted state carries the new note.
  Future<void> addAnalystUpdate(
    String caseNumber,
    String analystId,
    String text,
    String progress,
  );

  /// Signs the case's Verified Intel Report (Task 8.6) and refreshes the
  /// emitted state with the custody chain. Returns the signed report.
  Future<SignedReport> signVerifiedReport(String caseNumber);

  /// Queues a legal-aid handoff (Task 8.6) and refreshes the emitted state
  /// with the custody chain. Returns the handoff id.
  Future<String> queueLegalAidHandoff(String caseNumber);

  /// Releases resources.
  Future<void> close();
}
