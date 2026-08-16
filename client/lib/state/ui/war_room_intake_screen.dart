import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../pii/domain/pii_pipeline_port.dart';
import '../../repository/domain/idempotency_key.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../../war_room/data/file_picker_evidence_picker.dart';
import '../../war_room/domain/case_intake.dart';
import '../../war_room/domain/evidence_item.dart';
import '../../war_room/domain/evidence_ports.dart';
import '../../war_room/domain/intake_draft.dart';
import '../domain/war_room_bloc.dart';
import '../domain/war_room_state.dart';
import 'quick_exit_safe_screen.dart';
import 'war_room_masthead.dart';
import 'war_room_theme.dart';

/// The trauma-aware new-case intake flow (DESIGN.md §8.3) — one screen per
/// step, never overwhelming the victim. Steps:
///   1. SITUATION OVERVIEW — pick a situation category (radio).
///   2. YOUR SITUATION — describe what happened, in your own words.
///   3. EVIDENCE — encrypted-before-leaving note (upload lands in Task 8.2).
///   4. URGENCY — how urgent is this (with a safety-first notice).
///   5. CONSENT & SUBMIT — two required consents + optional Ledger opt-in.
///
/// Submitting files the case through the [WarRoomBloc] and reports the
/// assigned dossier stamp number via [onFiled].
///
/// SECURITY CHECKPOINT (Task 8.1): the whole flow is wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE). The form collects NO identity —
/// no phone, no name, no handle; [narrative] is case content (encrypted at
/// rest in Task 8.2), never identity.
class WarRoomIntakeScreen extends StatefulWidget {
  const WarRoomIntakeScreen({
    super.key,
    required this.bloc,
    this.picker,
    this.redactionPipeline,
    this.onFiled,
    this.onExit,
    this.onQuickExit,
    this.onPaused,
    this.draftStore,
    this.secureFlagService,
  });

  final WarRoomBloc bloc;

  /// Evidence picker seam (Task 8.2). Defaults to the production
  /// [FilePickerEvidencePicker]; tests inject an in-memory fake.
  final EvidencePicker? picker;

  /// PII redaction pipeline seam (Task 8.3). When provided, the narrative is
  /// scrubbed by the local pipeline (deterministic dictionary + local
  /// contextual detector) BEFORE the case is filed, and the plaintext buffer
  /// is wiped — the case payload then carries zero raw PII. When null
  /// (foundation/dev) the narrative is submitted as typed.
  final PiiRedactionPipeline? redactionPipeline;

  /// Reports the filed case stamp (e.g. `CC-0048`) after submission.
  final ValueChanged<String>? onFiled;

  /// Closes the flow (top-left ✕) — confirms when there is unsaved input.
  final VoidCallback? onExit;

  /// QUICK EXIT / panic button (Task 8.7): INSTANTLY wipes every transient
  /// buffer (narrative controller, evidence bytes, selections) and navigates
  /// to a neutral safe screen. When null, the screen pushes
  /// [QuickExitSafeScreen] itself; the host may wire this to exit the vault
  /// shell instead.
  final VoidCallback? onQuickExit;

  /// Fired after Pause & Save persists the encrypted draft (Task 8.7) — the
  /// host typically navigates away (the draft is resumable later).
  final VoidCallback? onPaused;

  /// Encrypted draft store seam (Task 8.7 Pause, Save & Resume). When null,
  /// Pause & Save is hidden and no resume surface is offered.
  final IntakeDraftStore? draftStore;

  /// FLAG_SECURE service seam (tests inject a recording fake).
  final SecureFlagService? secureFlagService;

  @override
  State<WarRoomIntakeScreen> createState() => _WarRoomIntakeScreenState();
}

class _WarRoomIntakeScreenState extends State<WarRoomIntakeScreen> {
  int _step = 1;
  bool _submitting = false;

  /// The intake session's local draft id — DEK-encrypted evidence attaches
  /// to it BEFORE the case is filed (Task 8.2).
  late final String _draftCaseId = 'DRAFT-${_idGen.generate()}';
  static final IdempotencyKeyGenerator _idGen = IdempotencyKeyGenerator();

  IntakeSituation? _situation;
  final TextEditingController _narrative = TextEditingController();
  IntakeUrgency? _urgency;
  bool _consentNotLegalAdvice = false;
  bool _consentLegalAidReferral = false;
  bool _optInLedger = false;

  /// The most recently picked evidence bytes still referenced by this
  /// screen (wiped on quick exit / cancel — memory hygiene, Task 8.7).
  final List<Uint8List> _transientBuffers = [];

  /// A saved draft available for resume (Task 8.7). Loaded in [initState]
  /// from the [IntakeDraftStore] seam; null when none / store absent.
  IntakeDraft? _resumeDraft;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    // Track evidence attached to this draft + encryption progress.
    _stateSub = widget.bloc.state.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _evidence
          ..clear()
          ..addAll(state.evidence.where((e) => e.caseNumber == _draftCaseId));
        _encrypting = state.encryptingEvidence;
        _evidenceError = state.evidenceError;
      });
    });
    _loadResumeDraft();
  }

  /// Loads the newest saved draft (if any) so step 1 can offer a resume
  /// surface. Never throws — a store failure just means no resume banner.
  Future<void> _loadResumeDraft() async {
    final store = widget.draftStore;
    if (store == null) {
      _draftLoaded = true;
      return;
    }
    try {
      final drafts = await store.listDrafts();
      if (!mounted) {
        return;
      }
      setState(() {
        _resumeDraft = drafts.isEmpty ? null : drafts.first;
        _draftLoaded = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _draftLoaded = true);
    }
  }

  /// True when the victim has entered ANY content since opening (used to
  /// gate the ✕ close behind a confirmation — no silent data loss).
  bool get _hasUnsavedInput =>
      _narrative.text.trim().isNotEmpty ||
      _situation != null ||
      _urgency != null ||
      _consentNotLegalAdvice ||
      _consentLegalAidReferral ||
      _optInLedger ||
      _evidence.isNotEmpty ||
      _step > 1;

  /// WIPES every transient in-memory buffer (Task 8.7 MEMORY HYGIENE):
  /// clears the narrative controller, zero-fills picked evidence bytes,
  /// drops the evidence list and all selections. Called on quick exit, on
  /// confirmed ✕ close, and after filing.
  void _wipeTransientState() {
    _narrative.clear();
    for (final buffer in _transientBuffers) {
      zeroFill(buffer);
    }
    _transientBuffers.clear();
    _evidence.clear();
    _situation = null;
    _urgency = null;
    _consentNotLegalAdvice = false;
    _consentLegalAidReferral = false;
    _optInLedger = false;
    _step = 1;
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    _narrative.dispose();
    super.dispose();
  }

  CaseIntakeSubmission _submissionFrom({required String narrative}) =>
      CaseIntakeSubmission(
        situation: _situation!,
        narrative: narrative,
        urgency: _urgency!,
        consentNotLegalAdvice: _consentNotLegalAdvice,
        consentLegalAidReferral: _consentLegalAidReferral,
        evidenceCount: _attachedEvidenceCount,
        draftCaseId: _draftCaseId,
        optInAnonymizedLedger: _optInLedger,
      );

  /// True when the two REQUIRED consents are checked (Step 5 gate). Uses a
  /// minimal probe so the gate does NOT re-run the redaction pipeline on
  /// every rebuild (the pipeline runs exactly once, at submit).
  bool get _consentComplete =>
      _consentNotLegalAdvice && _consentLegalAidReferral;

  /// Builds the submission exactly once, at submit time (Task 8.3): when a
  /// redaction pipeline is wired, the narrative is scrubbed here (regex
  /// dictionary → local contextual detector) and its plaintext buffer wiped
  /// before the case is filed. [redactionReport] carries only non-PII
  /// aggregate counts; [redactionApplied] is set so downstream consumers know
  /// the payload was scrubbed.
  CaseIntakeSubmission _buildSubmission() {
    final rawNarrative = _narrative.text.trim();
    final pipeline = widget.redactionPipeline;
    if (pipeline == null) {
      return _submissionFrom(narrative: rawNarrative);
    }
    final input = Uint8BufferInput(rawNarrative);
    final result = pipeline.redact(input);
    return CaseIntakeSubmission(
      situation: _situation!,
      narrative: result.redacted,
      urgency: _urgency!,
      consentNotLegalAdvice: _consentNotLegalAdvice,
      consentLegalAidReferral: _consentLegalAidReferral,
      evidenceCount: _attachedEvidenceCount,
      draftCaseId: _draftCaseId,
      optInAnonymizedLedger: _optInLedger,
      redactionReport: result.report,
      redactionApplied: true,
    );
  }

  /// Evidence attached to THIS draft (from the bloc stream, Task 8.2).
  final List<EvidenceSummary> _evidence = [];
  bool _encrypting = false;
  String? _evidenceError;
  StreamSubscription<WarRoomState>? _stateSub;

  int get _attachedEvidenceCount => _evidence.length;

  bool get _canContinue => switch (_step) {
        1 => _situation != null,
        2 => _narrative.text.trim().isNotEmpty,
        3 => true, // evidence is optional; attachments arrive in 8.2
        4 => _urgency != null,
        // Step 5 (consent & submit): both mandatory consents required.
        _ => _consentComplete,
      };

  Future<void> _continue() async {
    if (_step == 5) {
      await _submit();
      return;
    }
    setState(() => _step++);
  }

  void _back() {
    if (_step > 1) {
      setState(() => _step--);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      // Task 8.3: the redaction pipeline runs exactly ONCE per submission,
      // here — the plaintext narrative buffer is wiped inside the pipeline
      // and only the redacted text reaches the case store.
      final stamp = await widget.bloc.fileCase(_buildSubmission());
      // Memory hygiene: the case is filed — wipe every transient buffer.
      _wipeTransientState();
      widget.onFiled?.call(stamp);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _attachEvidence() async {
    final picker = widget.picker ?? _defaultPicker;
    final picked = await picker.pick();
    if (picked == null) {
      return; // cancelled
    }
    // Retain the plaintext bytes so they can be zero-filled on wipe
    // (memory hygiene — the filename dies with the pick, the bytes die
    // on wipe).
    _transientBuffers.add(picked.bytes);
    try {
      await widget.bloc.attachEvidence(_draftCaseId, picked);
    } catch (_) {
      // The bloc already surfaced a GENERIC error via state — never crash
      // the flow, never leak internals.
    }
  }

  /// QUICK EXIT / panic (Task 8.7): INSTANTLY wipes every transient buffer
  /// and routes to a neutral safe screen. No confirmation — the panic
  /// button must be one tap.
  Future<void> _quickExit() async {
    _wipeTransientState();
    if (!mounted) {
      return;
    }
    final onQuickExit = widget.onQuickExit;
    if (onQuickExit != null) {
      onQuickExit();
      return;
    }
    // Default: push the neutral safe fallback screen (host may pop the
    // whole vault shell instead via [onQuickExit]).
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuickExitSafeScreen(
          secureFlagService: widget.secureFlagService,
        ),
      ),
    );
  }

  /// Pause & Save (Task 8.7): persists the current form as an ENCRYPTED
  /// draft and lets the victim leave — they can resume any time.
  Future<void> _pauseAndSave() async {
    final store = widget.draftStore;
    if (store == null) {
      return;
    }
    final draft = IntakeDraft(
      draftId: _draftCaseId,
      step: _step,
      situation: _situation,
      narrative: _narrative.text.trim(),
      urgency: _urgency,
      consentNotLegalAdvice: _consentNotLegalAdvice,
      consentLegalAidReferral: _consentLegalAidReferral,
      optInAnonymizedLedger: _optInLedger,
      savedAt: DateTime.now(),
    );
    try {
      await store.saveDraft(draft);
      if (!mounted) {
        return;
      }
      // Non-destructive confirmation — the victim knows they can resume.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft saved securely — you can resume anytime.'),
        ),
      );
      widget.onPaused?.call();
    } catch (_) {
      if (!mounted) {
        return;
      }
      // Degrade gracefully — never a crash, never a stack trace.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the draft. Please try again.'),
        ),
      );
    }
  }

  /// Restores a saved draft into the form and jumps to its step.
  void _resume(IntakeDraft draft) {
    setState(() {
      _step = draft.step;
      _situation = draft.situation;
      _narrative.text = draft.narrative;
      _urgency = draft.urgency;
      _consentNotLegalAdvice = draft.consentNotLegalAdvice;
      _consentLegalAidReferral = draft.consentLegalAidReferral;
      _optInLedger = draft.optInAnonymizedLedger;
      _resumeDraft = null;
    });
  }

  /// Discards a saved draft (Start fresh) — with the store's own delete.
  Future<void> _discardDraft(IntakeDraft draft) async {
    final store = widget.draftStore;
    try {
      await store?.deleteDraft(draft.draftId);
    } catch (_) {
      // Degrade gracefully — the banner stays, nothing crashes.
    }
    if (!mounted) {
      return;
    }
    setState(() => _resumeDraft = null);
  }

  /// The ✕ close: with unsaved input, CONFIRM before discarding (no
  /// destructive reset without explicit confirmation); otherwise close
  /// immediately. QUICK EXIT remains the instant path.
  Future<void> _requestClose() async {
    if (!_hasUnsavedInput) {
      _wipeTransientState();
      widget.onExit?.call();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WarRoomTheme.manilaPaper,
        title: const Text('Leave without saving?'),
        content: const Text(
          'Your progress on this case will be cleared. '
          'You can pause and save to resume later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB52A2A),
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _wipeTransientState();
      widget.onExit?.call();
    }
  }

  static final EvidencePicker _defaultPicker = FilePickerEvidencePicker();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WarRoomTheme.manilaPaper,
      body: _secure(
        Column(
          children: [
            const WarRoomMasthead(label: 'File a New Case'),
            // Progress dots: [1●2○3○4○5○] + QUICK EXIT panic button.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _requestClose,
                    icon: const Icon(Icons.close,
                        size: 18, color: WarRoomTheme.muted),
                    tooltip: 'Close',
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _StepDots(current: _step, total: 5),
                  ),
                  TextButton(
                    onPressed: _quickExit,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB52A2A),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.exit_to_app, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'QUICK EXIT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            fontFamily: WarRoomTheme.monoFont,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _stepTitle(_step),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    fontFamily: WarRoomTheme.monoFont,
                    letterSpacing: 1.2,
                    color: WarRoomTheme.muted,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                children: [
                  if (_step == 1 && _draftLoaded && _resumeDraft != null)
                    _ResumeBanner(
                      draft: _resumeDraft!,
                      onResume: () => _resume(_resumeDraft!),
                      onDiscard: () => _discardDraft(_resumeDraft!),
                    ),
                  switch (_step) {
                    1 => _situationStep(),
                    2 => _narrativeStep(),
                    3 => _evidenceStep(),
                    4 => _urgencyStep(),
                    _ => _consentStep(),
                  },
                  const SizedBox(height: 16),
                  const _GroundingNote(),
                ],
              ),
            ),
            // Fixed action bar — Back / Pause & Save / Continue are ALWAYS
            // reachable (never scroll away; trauma-informed: no hunt for the
            // primary controls).
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: const BoxDecoration(
                color: WarRoomTheme.manilaPaper,
                border: Border(top: BorderSide(color: WarRoomTheme.divider)),
              ),
              child: Row(
                children: [
                  if (_step > 1)
                    OutlinedButton(
                      onPressed: _back,
                      child: const Text('Back'),
                    ),
                  if (widget.draftStore != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _submitting ? null : _pauseAndSave,
                      child: const Text('Pause & Save'),
                    ),
                  ],
                  const Spacer(),
                  FilledButton(
                    onPressed: _canContinue && !_submitting ? _continue : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: WarRoomTheme.amber,
                      disabledBackgroundColor: WarRoomTheme.divider,
                    ),
                    child: Text(
                        _step == 5 ? 'Submit case securely' : 'Continue →'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  static String _stepTitle(int step) => switch (step) {
        1 => 'STEP 1 OF 5 — SITUATION OVERVIEW',
        2 => 'STEP 2 OF 5 — YOUR SITUATION',
        3 => 'STEP 3 OF 5 — EVIDENCE',
        4 => 'STEP 4 OF 5 — URGENCY',
        _ => 'STEP 5 OF 5 — CONSENT & SUBMIT',
      };

  // --- Steps -------------------------------------------------------------

  Widget _situationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "You're in the right place.",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: WarRoomTheme.dossierInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'What best describes your situation?',
          style: TextStyle(fontSize: 14, color: WarRoomTheme.dossierInk),
        ),
        const SizedBox(height: 12),
        RadioGroup<IntakeSituation>(
          groupValue: _situation,
          onChanged: (v) => setState(() => _situation = v),
          child: Column(
            children: [
              for (final s in IntakeSituation.values)
                RadioListTile<IntakeSituation>(
                  title: Text(s.label, style: const TextStyle(fontSize: 14)),
                  value: s,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Nothing you share here is visible to anyone except the '
          'War Room analysts assigned to your case.',
          style: TextStyle(
            fontSize: 12,
            color: WarRoomTheme.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _narrativeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Describe what happened — in your own words. '
          'There is no wrong way to say it.',
          style: TextStyle(fontSize: 14, color: WarRoomTheme.dossierInk),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _narrative,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Write your account here…',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: WarRoomTheme.surface,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'You can stop and return to this at any time.',
          style: TextStyle(
            fontSize: 12,
            color: WarRoomTheme.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _evidenceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Share anything that might help the analysts. '
          'Screenshots, messages, usernames, links — anything.',
          style: TextStyle(fontSize: 14, color: WarRoomTheme.dossierInk),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: WarRoomTheme.amber),
          ),
          child: const Text(
            '⚠ Evidence is encrypted before leaving your device. '
            'Only assigned analysts can view it.',
            style: TextStyle(fontSize: 12, color: WarRoomTheme.dossierInk),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _encrypting ? null : _attachEvidence,
          icon: const Icon(Icons.attach_file, size: 18),
          label: const Text('Add evidence'),
        ),
        if (_encrypting) ...[
          const SizedBox(height: 10),
          const _EncryptingRow()
        ],
        if (_evidenceError != null) ...[
          const SizedBox(height: 10),
          _ErrorBanner(_evidenceError!)
        ],
        if (_evidence.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._evidence.map(_EvidenceChip.new)
        ],
      ],
    );
  }

  Widget _urgencyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How urgent is this?',
          style: TextStyle(fontSize: 14, color: WarRoomTheme.dossierInk),
        ),
        const SizedBox(height: 12),
        RadioGroup<IntakeUrgency>(
          groupValue: _urgency,
          onChanged: (v) => setState(() => _urgency = v),
          child: Column(
            children: [
              for (final u in IntakeUrgency.values)
                RadioListTile<IntakeUrgency>(
                  title: Text(u.label, style: const TextStyle(fontSize: 14)),
                  value: u,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your safety matters more than the case timeline. If you feel '
          'you are in immediate physical danger, please contact '
          'emergency services first.',
          style: TextStyle(
            fontSize: 12,
            color: WarRoomTheme.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _consentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Before we assign analysts:',
          style: TextStyle(fontSize: 14, color: WarRoomTheme.dossierInk),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          title: const Text(
            'I understand this service is provided by volunteer analysts '
            'and is not a substitute for legal advice.',
            style: TextStyle(fontSize: 13),
          ),
          value: _consentNotLegalAdvice,
          onChanged: (v) => setState(() => _consentNotLegalAdvice = v ?? false),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          title: const Text(
            'I agree that the platform may refer my case to legal aid '
            'partners if analysts recommend it.',
            style: TextStyle(fontSize: 13),
          ),
          value: _consentLegalAidReferral,
          onChanged: (v) =>
              setState(() => _consentLegalAidReferral = v ?? false),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          title: const Text(
            'I would like to be notified if I can publish an anonymized '
            'version of my case to the Daily Ledger to warn others '
            '(optional — you decide later).',
            style: TextStyle(fontSize: 13),
          ),
          value: _optInLedger,
          onChanged: (v) => setState(() => _optInLedger = v ?? false),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 10),
        const Text(
          'Your case is assigned a random number. Analysts see only that '
          'number and your evidence — not your username or karma profile.',
          style: TextStyle(
            fontSize: 12,
            color: WarRoomTheme.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// Inline encryption-progress row (Task 8.2) — shown while the DEK seal +
/// wrap + sealed enqueue runs. No filenames, no progress percentages with
/// content — just a spinner + a fixed label.
class _EncryptingRow extends StatelessWidget {
  const _EncryptingRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text(
          'Encrypting evidence…',
          style: TextStyle(
            fontSize: 12,
            color: WarRoomTheme.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// Generic evidence error banner (Task 8.2) — a fixed message, NEVER a
/// stack trace or internal detail.
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFB52A2A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFB52A2A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB52A2A)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A chip for one attached evidence item (Task 8.2).
///
/// SECURITY CHECKPOINT: renders ONLY the derived `mime · size` label via
/// [evidenceLabel] — the raw filename is never persisted, queued, logged,
/// or rendered (a filename can embed sensitive context).
class _EvidenceChip extends StatelessWidget {
  final EvidenceSummary summary;
  const _EvidenceChip(this.summary);

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: WarRoomTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WarRoomTheme.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 16, color: WarRoomTheme.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              evidenceLabel(s.mimeType, s.sizeBytes),
              style: const TextStyle(
                fontSize: 13,
                color: WarRoomTheme.dossierInk,
              ),
            ),
          ),
          const Text(
            'ENCRYPTED',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              fontFamily: WarRoomTheme.monoFont,
              letterSpacing: 0.8,
              color: WarRoomTheme.amber,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Task 8.7 resume surface: a saved draft exists and step 1 offers the
/// victim a choice — resume exactly where they paused, or start fresh.
///
/// SECURITY CHECKPOINT (8.7): the banner shows ONLY the saved step + a
/// generic description — never the narrative, never identity.
class _ResumeBanner extends StatelessWidget {
  final IntakeDraft draft;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  const _ResumeBanner({
    required this.draft,
    required this.onResume,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WarRoomTheme.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You have a saved draft',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: WarRoomTheme.dossierInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Paused at step ${draft.step} of 5. Resume where you left off '
            '— nothing is lost.',
            style: const TextStyle(fontSize: 12, color: WarRoomTheme.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                onPressed: onResume,
                style: FilledButton.styleFrom(
                  backgroundColor: WarRoomTheme.amber,
                ),
                child: const Text('Resume draft'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onDiscard,
                child: const Text('Start fresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Task 8.7 grounding note — the SAME fixed reassurance line on every
/// step. Trauma-informed framing: no pressure, no timers, the victim is in
/// control. Pure fixed copy — zero PII, zero case content.
class _GroundingNote extends StatelessWidget {
  const _GroundingNote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'You are in control. Nothing you write here is sent anywhere until '
      'you choose to submit it. You can pause and save at any step, or use '
      'QUICK EXIT to leave instantly.',
      style: TextStyle(
        fontSize: 12,
        color: WarRoomTheme.muted,
        fontStyle: FontStyle.italic,
        height: 1.5,
      ),
    );
  }
}

/// Progress dots `[1●2○3○4○5○]` (DESIGN.md §8.3).
class _StepDots extends StatelessWidget {
  final int current;
  final int total;

  const _StepDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: 8),
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= current ? WarRoomTheme.amber : Colors.transparent,
              border: Border.all(color: WarRoomTheme.muted),
            ),
            child: Text(
              '$i',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: WarRoomTheme.monoFont,
                color: i <= current ? Colors.white : WarRoomTheme.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
