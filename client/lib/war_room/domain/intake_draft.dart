import 'dart:convert';
import 'dart:typed_data';

import 'case_intake.dart';

/// A paused War Room intake (Task 8.7 — Pause, Save & Resume).
///
/// Captures the victim's in-progress form at any of the 5 steps so they can
/// pause and resume later WITHOUT losing their account. The narrative is
/// case CONTENT (never identity) and is sealed with AES-256-GCM before any
/// persistence — the at-rest row carries only the sealed envelope.
///
/// SECURITY CHECKPOINT (Task 8.7): the draft carries no phone, no name, no
/// handle — the same zero-identity intake contract as [CaseIntakeSubmission].
class IntakeDraft {
  /// UUID v4 draft id — doubles as the resume key.
  final String draftId;

  /// The step the victim paused on (1..5).
  final int step;

  final IntakeSituation? situation;
  final String narrative;
  final IntakeUrgency? urgency;

  final bool consentNotLegalAdvice;
  final bool consentLegalAidReferral;
  final bool optInAnonymizedLedger;

  final DateTime savedAt;

  const IntakeDraft({
    required this.draftId,
    required this.step,
    required this.situation,
    required this.narrative,
    required this.urgency,
    required this.consentNotLegalAdvice,
    required this.consentLegalAidReferral,
    required this.optInAnonymizedLedger,
    required this.savedAt,
  });

  /// True when the draft has no victim-entered content (nothing to lose).
  bool get isEmpty =>
      narrative.trim().isEmpty &&
      situation == null &&
      urgency == null &&
      !consentNotLegalAdvice &&
      !consentLegalAidReferral &&
      !optInAnonymizedLedger;
}

/// Strict wire frame for a paused intake draft (Task 8.7).
///
/// `v:1` JSON carrying ONLY the intake fields — situation/urgency enum
/// names, the victim-written narrative (case content), consent flags, and
/// the saved timestamp. ZERO identity fields. Unknown versions and
/// malformed frames are rejected (never partially decoded).
class IntakeDraftEnvelope {
  static const int version = 1;

  final String draftId;
  final int step;
  final String? situation;
  final String narrative;
  final String? urgency;
  final bool consentNotLegalAdvice;
  final bool consentLegalAidReferral;
  final bool optInAnonymizedLedger;
  final DateTime savedAt;

  const IntakeDraftEnvelope({
    required this.draftId,
    required this.step,
    required this.situation,
    required this.narrative,
    required this.urgency,
    required this.consentNotLegalAdvice,
    required this.consentLegalAidReferral,
    required this.optInAnonymizedLedger,
    required this.savedAt,
  });

  factory IntakeDraftEnvelope.fromDraft(IntakeDraft d) => IntakeDraftEnvelope(
        draftId: d.draftId,
        step: d.step,
        situation: d.situation?.name,
        narrative: d.narrative,
        urgency: d.urgency?.name,
        consentNotLegalAdvice: d.consentNotLegalAdvice,
        consentLegalAidReferral: d.consentLegalAidReferral,
        optInAnonymizedLedger: d.optInAnonymizedLedger,
        savedAt: d.savedAt,
      );

  /// The strict frame: `{"v":1,"draft_id":...,"step":...,"situation":...,"narrative":...,"urgency":...,"consents":...,"saved_at":...}`.
  String encode() => jsonEncode({
        'v': version,
        'draft_id': draftId,
        'step': step,
        'situation': situation,
        'narrative': narrative,
        'urgency': urgency,
        'consent_not_legal_advice': consentNotLegalAdvice,
        'consent_legal_aid_referral': consentLegalAidReferral,
        'opt_in_anonymized_ledger': optInAnonymizedLedger,
        'saved_at': savedAt.toUtc().toIso8601String(),
      });

  /// Strict decode — rejects wrong versions, missing fields, out-of-range
  /// steps, and invalid enum names. Never partially decodes.
  factory IntakeDraftEnvelope.decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('draft envelope is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('draft envelope must be a JSON object');
    }
    final v = decoded['v'];
    if (v != version) {
      throw FormatException('unsupported draft envelope version: $v');
    }
    final draftId = decoded['draft_id'];
    final step = decoded['step'];
    final situation = decoded['situation'];
    final narrative = decoded['narrative'];
    final urgency = decoded['urgency'];
    final consentNotLegalAdvice = decoded['consent_not_legal_advice'];
    final consentLegalAidReferral = decoded['consent_legal_aid_referral'];
    final optIn = decoded['opt_in_anonymized_ledger'];
    final savedAt = decoded['saved_at'];
    if (draftId is! String ||
        step is! int ||
        step < 1 ||
        step > 5 ||
        narrative is! String ||
        consentNotLegalAdvice is! bool ||
        consentLegalAidReferral is! bool ||
        optIn is! bool ||
        savedAt is! String) {
      throw const FormatException('draft envelope is missing a field');
    }
    if (situation != null && situation is! String) {
      throw const FormatException('draft envelope has an invalid situation');
    }
    if (urgency != null && urgency is! String) {
      throw const FormatException('draft envelope has an invalid urgency');
    }
    final at = DateTime.tryParse(savedAt);
    if (at == null) {
      throw const FormatException('draft envelope has an invalid timestamp');
    }
    IntakeSituation? situationValue;
    if (situation != null) {
      try {
        situationValue = IntakeSituation.values.byName(situation);
      } on ArgumentError {
        throw FormatException('unknown situation: $situation');
      }
    }
    IntakeUrgency? urgencyValue;
    if (urgency != null) {
      try {
        urgencyValue = IntakeUrgency.values.byName(urgency);
      } on ArgumentError {
        throw FormatException('unknown urgency: $urgency');
      }
    }
    return IntakeDraftEnvelope(
      draftId: draftId,
      step: step,
      situation: situationValue?.name,
      narrative: narrative,
      urgency: urgencyValue?.name,
      consentNotLegalAdvice: consentNotLegalAdvice,
      consentLegalAidReferral: consentLegalAidReferral,
      optInAnonymizedLedger: optIn,
      savedAt: at.toUtc(),
    );
  }
}

/// Port for persisting paused intake drafts (Task 8.7).
///
/// Implementations MUST seal the draft envelope (AES-256-GCM) before any
/// persistence — the at-rest row carries only ciphertext. The draft is
/// recoverable only by the local device key hierarchy.
abstract class IntakeDraftStore {
  /// Persists (or replaces) [draft], sealed at rest.
  Future<void> saveDraft(IntakeDraft draft);

  /// Loads the draft with [draftId], or null when absent.
  Future<IntakeDraft?> loadDraft(String draftId);

  /// Deletes the draft with [draftId].
  Future<void> deleteDraft(String draftId);

  /// All locally persisted drafts, newest saved first (resume surface).
  Future<List<IntakeDraft>> listDrafts();
}

/// Overwrites [bytes] with zeros — the memory-hygiene wipe for transient
/// sensitive buffers (picked evidence bytes, draft frames). Task 8.7
/// MEMORY HYGIENE: exiting/cancelling/quick-exiting zero-fills buffers
/// before releasing references.
void zeroFill(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}
