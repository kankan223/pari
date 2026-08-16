import 'analyst.dart';
import 'case_severity.dart';
import 'case_status.dart';
import 'severity_scoring.dart';

/// A War Room case (PRD §7.4 CASE entity, DESIGN.md §8.2/§8.4).
///
/// SECURITY CHECKPOINT (Task 8.1): the case carries ONLY the public dossier
/// stamp attributes — a generated case number (`CC-0047`), a victim-written
/// title, severity, status, timestamps and analyst COUNTS. No phones, no
/// blind hashes, no names, no payload content ever lives on the model that
/// reaches the widget tree. Evidence payloads arrive encrypted in Task 8.2
/// and are never part of this projection.
class WarRoomCase {
  /// Dossier stamp number, e.g. `CC-0047` — generated server-side/local,
  /// never derived from identity.
  final String caseNumber;

  /// Victim-written one-line summary (case content, not identity).
  final String title;

  /// Longer description shown on the detail view.
  final String description;

  final CaseSeverity severity;

  /// The deterministic keyword-triage output (Task 8.4) — score, signal
  /// counts and the SLA projection. Null for pre-8.4 seeds.
  final SeverityTriage? triage;

  /// Human-reviewed severity override (Task 8.4). Null until an analyst
  /// overrides the auto-score.
  final SeverityOverride? severityOverride;

  final CaseStatus status;

  /// True while the victim has paused the case (PRD §7.3-4 one-tap pause).
  final bool paused;

  final DateTime filedAt;

  /// Number of blinded analysts assigned (a count — never names/handles).
  final int analystCount;

  /// Estimated hours until the Verified Intel Report (SLA projection).
  final int? estReportHours;

  /// The immutable status timeline (DESIGN.md §8.4) in order.
  final List<CaseTimelineEntry> timeline;

  /// Analyst update notes (blinded — only text + timestamp + status chip,
  /// attributed via the BLINDED analyst handle, Task 8.5).
  final List<AnalystUpdate> updates;

  /// Skill-matched analyst assignments (Task 8.5) — blinded handles only.
  final List<CaseAssignment> assignments;

  const WarRoomCase({
    required this.caseNumber,
    required this.title,
    required this.description,
    required this.severity,
    required this.status,
    required this.filedAt,
    this.paused = false,
    this.analystCount = 0,
    this.estReportHours,
    this.timeline = const [],
    this.updates = const [],
    this.assignments = const [],
    this.triage,
    this.severityOverride,
  });

  /// Pauses (or unpauses) the case — status text gains a PAUSED marker but
  /// the lifecycle status is untouched (one-tap control, never destructive).
  WarRoomCase withPaused(bool value) => WarRoomCase(
        caseNumber: caseNumber,
        title: title,
        description: description,
        severity: severity,
        status: status,
        filedAt: filedAt,
        paused: value,
        analystCount: analystCount,
        estReportHours: estReportHours,
        timeline: timeline,
        updates: updates,
        assignments: assignments,
        triage: triage,
        severityOverride: severityOverride,
      );

  /// Marks the case withdrawn by the victim.
  WarRoomCase withStatus(CaseStatus next) => WarRoomCase(
        caseNumber: caseNumber,
        title: title,
        description: description,
        severity: severity,
        status: next,
        filedAt: filedAt,
        paused: paused,
        analystCount: analystCount,
        estReportHours: estReportHours,
        timeline: timeline,
        updates: updates,
        assignments: assignments,
        triage: triage,
        severityOverride: severityOverride,
      );

  /// Applies a human-reviewed severity override (Task 8.4): the displayed
  /// severity becomes [override]'s severity and the SLA projection follows
  /// the new band. The original triage is preserved for the audit trail.
  WarRoomCase withSeverityOverride(SeverityOverride override) => WarRoomCase(
        caseNumber: caseNumber,
        title: title,
        description: description,
        severity: override.newSeverity,
        status: status,
        filedAt: filedAt,
        paused: paused,
        analystCount: analystCount,
        estReportHours: SeverityScorer.slaHoursFor(override.newSeverity),
        timeline: timeline,
        updates: updates,
        assignments: assignments,
        triage: triage,
        severityOverride: override,
      );

  /// Attaches a blinded analyst update (Task 8.5). The note is attributed
  /// ONLY via the author's blinded handle — never a real identity.
  WarRoomCase withUpdate(AnalystUpdate update) => WarRoomCase(
        caseNumber: caseNumber,
        title: title,
        description: description,
        severity: severity,
        status: status,
        filedAt: filedAt,
        paused: paused,
        analystCount: analystCount,
        estReportHours: estReportHours,
        timeline: timeline,
        updates: [...updates, update],
        assignments: assignments,
        triage: triage,
        severityOverride: severityOverride,
      );
}

/// One checkpoint of the status timeline (DESIGN.md §8.4).
class CaseTimelineEntry {
  final String label;
  final DateTime? at;

  /// True = completed checkpoint, false = pending.
  final bool done;

  /// Free-text detail (e.g. `HIGH severity`, `2 assigned`) — rendered only
  /// as non-identity annotation.
  final String? detail;

  const CaseTimelineEntry({
    required this.label,
    required this.done,
    this.at,
    this.detail,
  });
}
