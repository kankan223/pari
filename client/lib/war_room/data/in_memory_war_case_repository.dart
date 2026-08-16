import 'dart:typed_data';

import '../domain/analyst.dart';
import '../domain/analyst_registry.dart';
import '../domain/case_intake.dart';
import '../domain/case_status.dart';
import '../domain/custody_log.dart';
import '../domain/severity_scoring.dart';
import '../domain/war_case_repository.dart';
import '../domain/war_room_case.dart';
import 'hmac_report_signer.dart';
import 'in_memory_analyst_registry.dart';
import 'in_memory_custody_log.dart';

/// In-memory, LOCAL-FIRST [WarCaseRepository] (data layer, Task 8.1).
///
/// Cases are served from the local store immediately — there is NO network
/// path here (evidence upload + encrypted persistence arrive in Task 8.2).
/// The stamp number is generated deterministically from the highest existing
/// number (never from identity).
///
/// SECURITY CHECKPOINT (Task 8.1): this file imports no
/// http/WebSocket/dart:io networking — the case list is local-first by
/// construction (verified by the 8.1 security checkpoint test). No raw
/// payload content is ever stored or emitted; intake narratives stay in the
/// domain model only until Task 8.2 encrypts them.
class InMemoryWarCaseRepository implements WarCaseRepository {
  final Map<String, WarRoomCase> _cases = {};
  int _nextNumber;

  /// Deterministic keyword-triage engine (Task 8.4) — injectable for tests;
  /// production uses the real [SeverityScorer].
  final SeverityScorer _scorer;

  /// Analyst pool + deterministic assignment engine (Task 8.5). Injectable
  /// for tests; production uses the canonical vetted pool.
  final AnalystRegistry _registry;

  /// Append-only custody log (Task 8.6). Injectable for tests; production
  /// uses the real SHA-256 chained log.
  final CustodyLog _custodyLog;

  /// HMAC signer for the Verified Intel Report (Task 8.6). Injectable for
  /// tests; production uses a device-keyed signer.
  final ReportSigner _reportSigner;

  /// Legal-aid handoff sink (Task 8.6). Injectable; null in the in-memory
  /// repository when no queue wiring is configured (queueing then still
  /// records the custody event but skips the enqueue).
  final LegalAidHandoffSink? _handoffSink;

  final DateTime Function() _clock;

  InMemoryWarCaseRepository({
    List<WarRoomCase> seed = const [],
    int nextNumber = 1,
    SeverityScorer? scorer,
    AnalystRegistry? registry,
    CustodyLog? custodyLog,
    ReportSigner? reportSigner,
    LegalAidHandoffSink? handoffSink,
    DateTime Function()? clock,
  })  : _scorer = scorer ?? const SeverityScorer(),
        _registry = registry ?? InMemoryAnalystRegistry.production(),
        _custodyLog = custodyLog ?? InMemoryCustodyLog(),
        _reportSigner = reportSigner ?? HmacReportSigner(key: Uint8List(32)),
        _handoffSink = handoffSink,
        _clock = clock ?? DateTime.now,
        _nextNumber = nextNumber {
    for (final c in seed) {
      _cases[c.caseNumber] = c;
    }
    // Keep the sequence monotonic above any seeded stamp.
    final maxSeed = seed.fold<int>(0, (acc, c) {
      final n = _stampNumber(c.caseNumber);
      return n > acc ? n : acc;
    });
    if (maxSeed >= _nextNumber) {
      _nextNumber = maxSeed + 1;
    }
  }

  /// Parses the numeric part of a `CC-0047` stamp; 0 when malformed.
  static int _stampNumber(String caseNumber) {
    final match = RegExp(r'^CC-(\d+)$').firstMatch(caseNumber);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1)!) ?? 0;
  }

  /// The next sequential dossier stamp: `CC-0001`, `CC-0047`, ...
  String _nextStamp() {
    final n = _nextNumber;
    _nextNumber++;
    return 'CC-${n.toString().padLeft(4, '0')}';
  }

  @override
  Future<List<WarRoomCase>> listCases() async {
    final cases = _cases.values.toList()
      // Newest filed first — the victim's own queue.
      ..sort((a, b) => b.filedAt.compareTo(a.filedAt));
    return cases;
  }

  @override
  Future<WarRoomCase?> getCaseById(String caseNumber) async =>
      _cases[caseNumber];

  @override
  Future<WarRoomCase> fileCase(CaseIntakeSubmission submission) async {
    final stamp = _nextStamp();
    final now = _clock();
    // Task 8.4: the DETERMINISTIC keyword engine auto-scores at triage
    // (replacing the Task 8.1 provisional hint). The intake's severity
    // floors still hold via the engine's floor merge — a serious category
    // or an immediate urgency can never be scored below its band.
    final triage = _scorer.score(
      narrative: submission.narrative,
      floorSeverity: submission.situation.baseSeverity,
      urgency: submission.urgency,
    );
    // Task 8.5: skill-matched auto-assignment — vetted analysts carrying
    // the situation's required skills take the case (least-loaded first,
    // cap-enforced, deterministic). Assignment happens at file time so the
    // victim sees their blinded team immediately (offline-first).
    final assignments = await _registry.assignToCase(
      caseNumber: stamp,
      skills: AnalystSkill.forSituation(submission.situation),
      at: now,
    );

    // Task 8.6: every lifecycle transition is recorded in the append-only
    // custody log (hash-chained, tamper-evident).
    final custody = _custodyLog;
    await custody.append(await custody.buildEvent(
      caseNumber: stamp,
      type: CustodyEventType.caseFiled,
      actor: 'VICTIM',
      at: now,
    ));
    await custody.append(await custody.buildEvent(
      caseNumber: stamp,
      type: CustodyEventType.autoTriage,
      actor: 'SYSTEM',
      at: now,
    ));
    for (final a in assignments) {
      await custody.append(await custody.buildEvent(
        caseNumber: stamp,
        type: CustodyEventType.analystAssigned,
        actor: a.analystId,
        at: now,
      ));
    }
    // Foundation timeline mirrors DESIGN.md §8.4 (filed → triage → ...).
    final filedCase = WarRoomCase(
      caseNumber: stamp,
      title: _titleFrom(submission),
      description: submission.narrative,
      severity: triage.severity,
      triage: triage,
      status: assignments.isEmpty
          ? CaseStatus.underInvestigation
          : CaseStatus.investigationOngoing,
      filedAt: now,
      analystCount: assignments.length,
      assignments: assignments,
      estReportHours: triage.slaHours,
      timeline: [
        CaseTimelineEntry(
          label: 'Case filed',
          at: now,
          done: true,
          detail: submission.situation.label,
        ),
        CaseTimelineEntry(
          label: 'Auto-triage complete',
          done: true,
          detail: '${triage.severity.label} · ${triage.slaHours}h SLA',
        ),
        CaseTimelineEntry(
          label: 'Analysts assigned',
          done: assignments.isNotEmpty,
          detail: assignments.isEmpty
              ? 'Awaiting vetted analysts'
              : '${assignments.length} vetted analyst'
                  '${assignments.length == 1 ? '' : 's'} — skill-matched',
        ),
        const CaseTimelineEntry(
          label: 'Investigation ongoing',
          done: false,
        ),
        const CaseTimelineEntry(label: 'Report ready', done: false),
        const CaseTimelineEntry(label: 'Choose next step', done: false),
      ],
    );
    _cases[stamp] = filedCase;
    return filedCase;
  }

  /// The victim's one-line title: the situation category + a short marker.
  /// This is case CONTENT (user-authored category), never identity.
  static String _titleFrom(CaseIntakeSubmission s) => s.situation.label;

  @override
  Future<WarRoomCase> setPaused(String caseNumber, bool paused) async {
    final c = _cases[caseNumber];
    if (c == null) {
      throw StateError('unknown case: $caseNumber');
    }
    final updated = c.withPaused(paused);
    _cases[caseNumber] = updated;
    return updated;
  }

  @override
  Future<WarRoomCase> withdraw(String caseNumber) async {
    final c = _cases[caseNumber];
    if (c == null) {
      throw StateError('unknown case: $caseNumber');
    }
    // Withdraw is final — the pause marker is meaningless afterwards. The
    // assigned analysts' load is released (Task 8.5).
    for (final a in c.assignments) {
      await _registry.releaseFromCase(
        caseNumber: caseNumber,
        analystId: a.analystId,
      );
    }
    // Task 8.6: record the withdrawal in the custody chain.
    await _custodyLog.append(await _custodyLog.buildEvent(
      caseNumber: caseNumber,
      type: CustodyEventType.caseWithdrawn,
      actor: 'VICTIM',
      at: _clock(),
    ));
    final updated = c.withPaused(false).withStatus(CaseStatus.withdrawn);
    _cases[caseNumber] = updated;
    return updated;
  }

  /// Posts a blinded analyst update (Task 8.5 blind-review contract): the
  /// note is attributed ONLY via the author's blinded handle.
  @override
  Future<WarRoomCase> addAnalystUpdate(
    String caseNumber,
    String analystId,
    String text,
    String progress,
  ) async {
    final c = _cases[caseNumber];
    if (c == null) {
      throw StateError('unknown case: $caseNumber');
    }
    // Only an assigned analyst may post on the case (blind-review
    // enforcement: the author handle must be in the case's assignments).
    final assigned = c.assignments.any((a) => a.analystId == analystId);
    if (!assigned) {
      throw StateError('analyst $analystId not assigned to $caseNumber');
    }
    final updated = c.withUpdate(AnalystUpdate(
      analystId: analystId,
      text: text,
      at: _clock(),
      progress: progress,
    ));
    _cases[caseNumber] = updated;
    // Task 8.6: the update is a custody event, attributed to the blinded
    // author handle.
    await _custodyLog.append(await _custodyLog.buildEvent(
      caseNumber: caseNumber,
      type: CustodyEventType.analystUpdate,
      actor: analystId,
      at: _clock(),
    ));
    return updated;
  }

  @override
  Future<WarRoomCase> overrideSeverity(
    String caseNumber,
    SeverityOverride override,
  ) async {
    final c = _cases[caseNumber];
    if (c == null) {
      throw StateError('unknown case: $caseNumber');
    }
    if (override.reason.trim().isEmpty) {
      throw ArgumentError('severity override requires a reason');
    }
    final updated = c.withSeverityOverride(override);
    _cases[caseNumber] =
        updated; // Task 8.6: the override is a custody event — the blinded lead analyst
    // (first assignment) or VICTIM when no team is on the case yet.
    final actor =
        c.assignments.isEmpty ? 'VICTIM' : c.assignments.first.analystId;
    await _custodyLog.append(await _custodyLog.buildEvent(
      caseNumber: caseNumber,
      type: CustodyEventType.severityOverride,
      actor: actor,
      at: _clock(),
    ));
    return updated;
  }

  @override
  Future<List<CustodyEvent>> custodyEvents(String caseNumber) =>
      _custodyLog.entries(caseNumber);

  @override
  Future<bool> verifyCustodyIntegrity() => _custodyLog.verifyIntegrity();

  @override
  Future<SignedReport> signVerifiedReport(String caseNumber) async {
    final c = _cases[caseNumber];
    if (c == null) {
      throw StateError('unknown case: $caseNumber');
    }
    final report = VerifiedIntelReport(
      caseNumber: c.caseNumber,
      severityLabel: c.severity.label,
      slaHours: c.estReportHours ?? SeverityScorer.slaHoursFor(c.severity),
      analystCount: c.analystCount,
      filedAt: c.filedAt,
      stageLine: c.status.label,
    );
    final signed = await _reportSigner.sign(
        report); // Task 8.6: signing is a custody event, attributed to the blinded lead.
    final actor =
        c.assignments.isEmpty ? 'VICTIM' : c.assignments.first.analystId;
    await _custodyLog.append(await _custodyLog.buildEvent(
      caseNumber: caseNumber,
      type: CustodyEventType.reportSigned,
      actor: actor,
      at: _clock(),
    ));
    return signed;
  }

  @override
  Future<String> queueLegalAidHandoff(String caseNumber) async {
    final c = _cases[caseNumber];
    if (c == null) {
      throw StateError('unknown case: $caseNumber');
    }
    if (_handoffSink != null) {
      final report = await signVerifiedReport(caseNumber);
      final analystId =
          c.assignments.isEmpty ? 'VICTIM' : c.assignments.first.analystId;
      // The sink mints the UUID v4 id (the idempotency key) — pass a draft.
      final handoff = LegalAidHandoff(
        id: '',
        caseNumber: caseNumber,
        reportSignature: report.signature,
        analystId: analystId,
        queuedAt: _clock(),
      );
      final id = await _handoffSink.queue(handoff);
      await _custodyLog.append(await _custodyLog.buildEvent(
        caseNumber: caseNumber,
        type: CustodyEventType.handoffQueued,
        actor: analystId,
        at: _clock(),
      ));
      return id;
    }
    // No queue wiring (in-memory repository without a sink): record the
    // event so the flow is still observable, return a stable non-id.
    final analystId =
        c.assignments.isEmpty ? 'VICTIM' : c.assignments.first.analystId;
    await _custodyLog.append(await _custodyLog.buildEvent(
      caseNumber: caseNumber,
      type: CustodyEventType.handoffQueued,
      actor: analystId,
      at: _clock(),
    ));
    return '$caseNumber-handoff';
  }
}
