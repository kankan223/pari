import 'dart:async';

import '../../war_room/domain/case_intake.dart';
import '../../war_room/domain/custody_log.dart';
import '../../war_room/domain/evidence_item.dart';
import '../../war_room/domain/evidence_ports.dart';
import '../../war_room/domain/severity_scoring.dart';
import '../../war_room/domain/war_case_repository.dart';
import '../../war_room/domain/war_room_case.dart';
import '../domain/war_room_bloc.dart';
import '../domain/war_room_state.dart';

/// Local-cache-backed [WarRoomBloc] (data layer, Task 8.1/8.2).
///
/// Reads cases ONLY from the injected [WarCaseRepository] — the offline-first
/// contract. Evidence (Task 8.2) flows through the optional [EvidenceSink]:
/// the DEK-seal + wrap + sealed enqueue happen inside the sink; this bloc
/// only surfaces progress + UI-safe [EvidenceSummary]s. Never touches the
/// network.
class LocalWarRoomBloc implements WarRoomBloc {
  final WarCaseRepository _repository;

  /// Evidence persistence seam (Task 8.2). When null (foundation tests), an
  /// attach attempt degrades to a generic error — never a crash.
  final EvidenceSink? _evidenceSink;

  final StreamController<WarRoomState> _controller =
      StreamController<WarRoomState>.broadcast();

  /// Last emitted state — used to re-resolve the opened case on refresh.
  WarRoomState? _last;

  /// Monotonic snapshot sequence — a stale pull can never overwrite a
  /// fresher one (codebase convention, cf. Task 6.2/7.1).
  int _seq = 0;

  LocalWarRoomBloc({
    required WarCaseRepository repository,
    EvidenceSink? evidenceSink,
  })  : _repository = repository,
        _evidenceSink = evidenceSink;

  @override
  Stream<WarRoomState> get state => _controller.stream;

  @override
  Future<void> start() async {
    await _emit();
  }

  @override
  Future<void> refresh() async {
    await _emit();
  }

  Future<void> _emit() async {
    final seq = ++_seq;
    // Preserve the currently opened case (by stamp) across refreshes so
    // pause/withdraw mutations reflect in the open detail view.
    final selectedNumber = _last?.selected?.caseNumber;
    try {
      final cases = await _repository.listCases();
      if (seq != _seq) {
        return; // stale — a newer snapshot already landed.
      }
      WarRoomCaseSummary? selected;
      if (selectedNumber != null) {
        for (final c in cases) {
          if (c.caseNumber == selectedNumber) {
            selected = await _summaryWithCustody(c);
            break;
          }
        }
      }
      _last = WarRoomState(
        status: WarRoomStatus.loaded,
        cases: cases.map(WarRoomCaseSummary.from).toList(),
        selected: selected,
      );
      _controller.add(_last!);
    } catch (_) {
      if (seq != _seq) {
        return;
      }
      _last = const WarRoomState(
        status: WarRoomStatus.error,
        cases: [],
      );
      _controller.add(_last!);
    }
  }

  @override
  Future<void> openCase(String caseNumber) async {
    final c = await _repository.getCaseById(caseNumber);
    if (c == null) {
      return;
    }
    final summary = await _summaryWithCustody(c);
    // Re-read the list so the emitted state stays consistent with the store.
    final cases =
        (await _repository.listCases()).map(WarRoomCaseSummary.from).toList();
    _last = WarRoomState(
      status: WarRoomStatus.loaded,
      cases: cases,
      selected: summary,
    );
    _controller.add(_last!);
  }

  @override
  Future<void> closeCase() async {
    final cases =
        (await _repository.listCases()).map(WarRoomCaseSummary.from).toList();
    _last = WarRoomState(
      status: WarRoomStatus.loaded,
      cases: cases,
      selected: null,
    );
    _controller.add(_last!);
  }

  @override
  Future<String> fileCase(CaseIntakeSubmission submission) async {
    final filed = await _repository.fileCase(submission);
    // Refresh the list so the new case appears in the victim's queue.
    await _emit();
    return filed.caseNumber;
  }

  @override
  Future<void> setPaused(String caseNumber, bool paused) async {
    await _repository.setPaused(caseNumber, paused);
    await _emit();
  }

  @override
  Future<void> withdraw(String caseNumber) async {
    await _repository.withdraw(caseNumber);
    await _emit();
  }

  @override
  Future<String> attachEvidence(
      String draftCaseId, PickedEvidence evidence) async {
    final sink = _evidenceSink;
    if (sink == null) {
      _emitWithError('Evidence is not available right now.');
      throw StateError('no evidence sink configured');
    }
    // Surface encryption progress to the UI, then encrypt + queue. The
    // bloc must never crash when evidence is attached before [start] has
    // run — fall back to the initial state as the emission base.
    _last = (_last ?? const WarRoomState.initial())
        .copyWith(encryptingEvidence: true);
    _controller.add(_last!);
    try {
      final id = await sink.addEvidence(draftCaseId, evidence);
      await _emitEvidenceLoaded();
      return id;
    } catch (_) {
      // Generic, deterministic — never a stack trace or internal detail.
      _last = (_last ?? const WarRoomState.initial()).copyWith(
        encryptingEvidence: false,
        evidenceError: 'Could not encrypt this file. Please try again.',
      );
      _controller.add(_last!);
      rethrow;
    }
  }

  @override
  Future<void> refreshEvidence() async {
    await _emitEvidenceLoaded();
  }

  @override
  Future<void> overrideSeverity(
      String caseNumber, SeverityOverride override) async {
    await _repository.overrideSeverity(caseNumber, override);
    await _emit();
  }

  @override
  Future<void> addAnalystUpdate(
    String caseNumber,
    String analystId,
    String text,
    String progress,
  ) async {
    await _repository.addAnalystUpdate(caseNumber, analystId, text, progress);
    await _emit();
  }

  @override
  Future<SignedReport> signVerifiedReport(String caseNumber) async {
    final signed = await _repository.signVerifiedReport(caseNumber);
    await _emit();
    return signed;
  }

  @override
  Future<String> queueLegalAidHandoff(String caseNumber) async {
    final id = await _repository.queueLegalAidHandoff(caseNumber);
    await _emit();
    return id;
  }

  /// Attaches the case's custody chain (Task 8.6) to its summary so the
  /// detail view can render the immutable log.
  Future<WarRoomCaseSummary> _summaryWithCustody(WarRoomCase c) async {
    final custodyEvents = await _repository.custodyEvents(c.caseNumber);
    final summary = WarRoomCaseSummary.from(c);
    return WarRoomCaseSummary(
      caseNumber: summary.caseNumber,
      title: summary.title,
      description: summary.description,
      severity: summary.severity,
      status: summary.status,
      paused: summary.paused,
      filedAt: summary.filedAt,
      analystCount: summary.analystCount,
      estReportHours: summary.estReportHours,
      timeline: summary.timeline,
      updates: summary.updates,
      assignments: summary.assignments,
      custodyEvents: custodyEvents,
      triage: summary.triage,
      severityOverride: summary.severityOverride,
    );
  }

  Future<void> _emitEvidenceLoaded() async {
    final sink = _evidenceSink;
    if (sink == null) {
      return;
    }
    try {
      final records = await sink.localEvidence();
      final summaries = records
          .map((r) => EvidenceSummary(
                id: r.id,
                caseNumber: r.caseNumber,
                sizeBytes: r.sizeBytes,
                mimeType: r.mimeType,
                createdAt: r.createdAt,
              ))
          .toList();
      _last = (_last ?? const WarRoomState.initial()).copyWith(
        evidence: summaries,
        encryptingEvidence: false,
        evidenceError: null,
      );
      _controller.add(_last!);
    } catch (_) {
      // Degrade gracefully — evidence simply stays unreloaded.
    }
  }

  void _emitWithError(String message) {
    _last = _last?.copyWith(evidenceError: message);
    _controller.add(_last!);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}
