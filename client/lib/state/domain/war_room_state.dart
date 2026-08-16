import '../../war_room/domain/analyst.dart';
import '../../war_room/domain/case_severity.dart';
import '../../war_room/domain/case_status.dart';
import '../../war_room/domain/custody_log.dart';
import '../../war_room/domain/severity_scoring.dart';
import '../../war_room/domain/war_room_case.dart';

/// UI-safe projection of a [WarRoomCase].
///
/// SECURITY CHECKPOINT (Task 8.1): carries ONLY the non-PII dossier stamp
/// attributes — case number, title, severity, status, timestamps, analyst
/// COUNTS. Never identity, never payload content.
class WarRoomCaseSummary {
  final String caseNumber;
  final String title;
  final String description;
  final CaseSeverity severity;
  final CaseStatus status;
  final bool paused;
  final DateTime filedAt;
  final int analystCount;
  final int? estReportHours;
  final List<CaseTimelineEntry> timeline;
  final List<AnalystUpdate> updates;

  /// Skill-matched analyst assignments (Task 8.5) — blinded handles only.
  final List<CaseAssignment> assignments;

  /// Append-only custody chain (Task 8.6) — fixed event labels + timestamps
  /// + blinded actors. Never identity, never payload content.
  final List<CustodyEvent> custodyEvents;

  /// Deterministic keyword-triage output (Task 8.4) — rendered in the
  /// detail triage section; null for pre-8.4 seeds.
  final SeverityTriage? triage;

  /// Human-reviewed severity override (Task 8.4); null until applied.
  final SeverityOverride? severityOverride;

  const WarRoomCaseSummary({
    required this.caseNumber,
    required this.title,
    required this.description,
    required this.severity,
    required this.status,
    required this.paused,
    required this.filedAt,
    required this.analystCount,
    required this.estReportHours,
    required this.timeline,
    required this.updates,
    required this.assignments,
    this.custodyEvents = const [],
    this.triage,
    this.severityOverride,
  });

  factory WarRoomCaseSummary.from(WarRoomCase c) => WarRoomCaseSummary(
        caseNumber: c.caseNumber,
        title: c.title,
        description: c.description,
        severity: c.severity,
        status: c.status,
        paused: c.paused,
        filedAt: c.filedAt,
        analystCount: c.analystCount,
        estReportHours: c.estReportHours,
        timeline: c.timeline,
        updates: c.updates,
        assignments: c.assignments,
        triage: c.triage,
        severityOverride: c.severityOverride,
      );
}

/// UI-safe projection of a locally persisted evidence item (Task 8.2).
///
/// SECURITY CHECKPOINT (Task 8.2): carries ONLY non-sensitive metadata —
/// id, size, mime, timestamp, draft case ref. NO filename, NO path, NO
/// identity: the UI renders the derived `mime · size` label only.
class EvidenceSummary {
  final String id;
  final String caseNumber;
  final int sizeBytes;
  final String mimeType;
  final DateTime createdAt;

  const EvidenceSummary({
    required this.id,
    required this.caseNumber,
    required this.sizeBytes,
    required this.mimeType,
    required this.createdAt,
  });
}

/// Lifecycle of the case list load.
enum WarRoomStatus { loading, loaded, error }

/// Immutable BLoC state for the War Room (Task 8.1/8.2).
class WarRoomState {
  final WarRoomStatus status;
  final List<WarRoomCaseSummary> cases;

  /// The opened case detail, when a case is selected.
  final WarRoomCaseSummary? selected;

  /// Locally persisted, DEK-encrypted evidence items (Task 8.2).
  final List<EvidenceSummary> evidence;

  /// True while an evidence item is being encrypted + queued (Task 8.2).
  final bool encryptingEvidence;

  /// Generic evidence error (never a stack trace / internal detail).
  final String? evidenceError;

  const WarRoomState({
    required this.status,
    required this.cases,
    this.selected,
    this.evidence = const [],
    this.encryptingEvidence = false,
    this.evidenceError,
  });

  const WarRoomState.initial()
      : status = WarRoomStatus.loading,
        cases = const [],
        selected = null,
        evidence = const [],
        encryptingEvidence = false,
        evidenceError = null;

  WarRoomState copyWith({
    WarRoomStatus? status,
    List<WarRoomCaseSummary>? cases,
    WarRoomCaseSummary? selected,
    bool clearSelected = false,
    List<EvidenceSummary>? evidence,
    bool? encryptingEvidence,
    bool clearEvidenceError = false,
    String? evidenceError,
    WarRoomCaseSummary Function(WarRoomCaseSummary)? selectedTransform,
  }) {
    final nextSelected = clearSelected ? null : (selected ?? this.selected);
    return WarRoomState(
      status: status ?? this.status,
      cases: cases ?? this.cases,
      selected: nextSelected == null
          ? null
          : (selectedTransform?.call(nextSelected) ?? nextSelected),
      evidence: evidence ?? this.evidence,
      encryptingEvidence: encryptingEvidence ?? this.encryptingEvidence,
      evidenceError:
          clearEvidenceError ? null : (evidenceError ?? this.evidenceError),
    );
  }
}
