import 'dart:convert';
import 'dart:typed_data';

/// Immutable custody event types (Task 8.6, DESIGN.md §8.6 CHAIN OF CUSTODY).
///
/// Fixed, non-sensitive labels — the ONLY text that ever appears in the
/// custody log. Events carry no narrative, no payload, no identity.
enum CustodyEventType {
  caseFiled('CASE FILED'),
  autoTriage('AUTO-TRIAGE'),
  analystAssigned('ANALYSTS ASSIGNED'),
  severityOverride('SEVERITY OVERRIDE'),
  analystUpdate('ANALYST UPDATE'),
  reportSigned('REPORT SIGNED'),
  handoffQueued('LEGAL-AID HANDOFF QUEUED'),
  caseWithdrawn('CASE WITHDRAWN');

  const CustodyEventType(this.label);

  /// The fixed classification label rendered in the custody viewer.
  final String label;
}

/// One append-only custody event (Task 8.6).
///
/// IMMUTABILITY: every event carries [prevHash] (the [selfHash] of the
/// previous event in the case's chain — a 64-hex zero string for the first)
/// and its own [selfHash] = SHA-256 over the event's canonical bytes. Any
/// modification of a past event breaks every subsequent link, so
/// [CustodyLog.verifyIntegrity] detects tampering by recomputing the chain.
///
/// SECURITY CHECKPOINT (8.6): events carry ONLY fixed type labels, a
/// blinded actor (`VICTIM` or an `AN-####` analyst handle), the case stamp,
/// and a timestamp. No names, no payload bytes, no hashes of identity.
class CustodyEvent {
  /// Monotonic per-case sequence (0-based).
  final int seq;

  /// The case this event belongs to (a generated `CC-####` stamp).
  final String caseNumber;

  final CustodyEventType type;

  /// The blinded actor: `VICTIM` or an `AN-####` analyst handle. Never a
  /// real name/email/phone.
  final String actor;

  final DateTime at;

  /// selfHash of the previous event in the chain (64-hex zeros for seq 0).
  final String prevHash;

  /// SHA-256 over this event's canonical bytes (64 hex chars).
  final String selfHash;

  const CustodyEvent({
    required this.seq,
    required this.caseNumber,
    required this.type,
    required this.actor,
    required this.at,
    required this.prevHash,
    required this.selfHash,
  });

  /// The deterministic canonical serialization the self-hash covers:
  /// `seq|caseNumber|type|actor|atUs|prevHash`. Stable across devices.
  String canonicalString() =>
      '$seq|$caseNumber|${type.name}|$actor|${at.microsecondsSinceEpoch}|$prevHash';

  /// The chain-link fields as a stable JSON object (viewer + debugging —
  /// contains no identity).
  Map<String, dynamic> toJson() => {
        'seq': seq,
        'caseNumber': caseNumber,
        'type': type.name,
        'actor': actor,
        'at': at.toUtc().toIso8601String(),
        'prevHash': prevHash,
        'selfHash': selfHash,
      };

  /// Recomputes this event's self-hash over its own fields (used by
  /// [CustodyLog.verifyIntegrity] — does NOT trust the stored hash).
  Future<Uint8List> recomputeSelfHash(Sha256Hasher hasher) =>
      hasher.hash(utf8.encode(canonicalString()));

  @override
  String toString() => toJson().toString();
}

/// SHA-256 hashing seam (Task 8.6).
///
/// Injectable so tests can use a deterministic/recording hasher, and so the
/// production default (real SHA-256 via the `cryptography` package) is the
/// only crypto dependency of the custody chain. Hashing is the ONLY
/// primitive used — the log never encrypts or decrypts payloads.
abstract class Sha256Hasher {
  Future<Uint8List> hash(List<int> bytes);
}

/// Port for the append-only custody log (Task 8.6).
///
/// The log is APPEND-ONLY by contract: there is no update/delete — entries
/// only accumulate. [verifyIntegrity] walks every case's chain and returns
/// false the moment a stored hash disagrees with a recomputation (tamper).
///
/// SECURITY CHECKPOINT (8.6): the log is immutable — a modified, inserted,
/// or reordered event is detectable. Implementations must never expose a
/// mutation path beyond [append].
abstract class CustodyLog {
  /// Builds a correctly-chained event for the NEXT position of
  /// [caseNumber]: the sequence, prevHash link (zeros for the first event)
  /// and self-hash are all derived here so callers cannot construct a
  /// mis-linked event. The event is NOT appended until [append] is called.
  Future<CustodyEvent> buildEvent({
    required String caseNumber,
    required CustodyEventType type,
    required String actor,
    required DateTime at,
  });

  /// Appends one event to its case's chain. [event.seq] must equal the
  /// next sequence for the case and [event.prevHash] must equal the last
  /// event's selfHash (or 64-hex zeros for the first) — a mismatch throws.
  Future<void> append(CustodyEvent event);

  /// All events for [caseNumber], oldest first (append order).
  Future<List<CustodyEvent>> entries(String caseNumber);

  /// True when every case's chain recomputes exactly (no tampering).
  Future<bool> verifyIntegrity();

  /// The event that closed a case's chain (last append), or null.
  Future<CustodyEvent?> lastEvent(String caseNumber);
}

/// The Verified Intel Report (Task 8.6) — the deterministic, non-PII
/// summary an analyst team produces for a case.
///
/// SECURITY CHECKPOINT (8.6): the report carries ONLY public dossier
/// attributes (stamp, severity, SLA, analyst count, filed date, fixed
/// stage line). No narrative, no evidence bytes, no identity.
class VerifiedIntelReport {
  final String caseNumber;
  final String severityLabel;
  final int slaHours;
  final int analystCount;
  final DateTime filedAt;
  final String stageLine;

  const VerifiedIntelReport({
    required this.caseNumber,
    required this.severityLabel,
    required this.slaHours,
    required this.analystCount,
    required this.filedAt,
    required this.stageLine,
  });

  /// The canonical report text that gets HMAC-signed — deterministic,
  /// stable across devices, non-PII.
  String canonicalText() => [
        'VERIFIED INTEL REPORT',
        'CASE #$caseNumber',
        'SEVERITY: $severityLabel',
        'SLA TARGET: ${slaHours}h',
        'ANALYSTS: $analystCount (blinded)',
        'FILED: ${filedAt.toUtc().toIso8601String()}',
        'STAGE: $stageLine',
      ].join('\n');
}

/// A report + its HMAC-SHA256 signature (Task 8.6).
class SignedReport {
  final VerifiedIntelReport report;

  /// Base64url HMAC-SHA256 signature over [report.canonicalText] with the
  /// device-held signing key.
  final String signature;

  final DateTime signedAt;

  const SignedReport({
    required this.report,
    required this.signature,
    required this.signedAt,
  });

  Map<String, dynamic> toJson() => {
        'caseNumber': report.caseNumber,
        'signature': signature,
        'signedAt': signedAt.toUtc().toIso8601String(),
      };
}

/// Port for HMAC-signing Verified Intel Reports (Task 8.6).
abstract class ReportSigner {
  /// Signs [report] with the device-held key. Deterministic — the same
  /// report always yields the same signature.
  Future<SignedReport> sign(VerifiedIntelReport report);

  /// True when [signed].signature is a valid HMAC over the report text.
  Future<bool> verify(SignedReport signed);
}

/// A legal-aid handoff request (Task 8.6 — legal-aid handoff webhook
/// integration). Carries the case stamp, the report signature reference,
/// and a blinded analyst handle — zero identity.
class LegalAidHandoff {
  /// UUID v4 id — doubles as the sync idempotency key.
  final String id;

  final String caseNumber;

  /// The base64url HMAC signature of the accompanying Verified Intel
  /// Report (the handoff is keyed to the signed report).
  final String reportSignature;

  /// The blinded analyst who prepared the handoff (`AN-####`).
  final String analystId;

  final DateTime queuedAt;

  const LegalAidHandoff({
    required this.id,
    required this.caseNumber,
    required this.reportSignature,
    required this.analystId,
    required this.queuedAt,
  });
}

/// Strict wire frame for a legal-aid handoff (Task 8.6).
///
/// `v:1` JSON with ZERO identity fields: handoff id, case stamp, report
/// signature reference, blinded analyst handle, queued timestamp. Unknown
/// versions and malformed frames are rejected (never partially decoded).
class LegalAidHandoffEnvelope {
  static const int version = 1;

  final String id;
  final String caseNumber;
  final String reportSignature;
  final String analystId;
  final DateTime queuedAt;

  const LegalAidHandoffEnvelope({
    required this.id,
    required this.caseNumber,
    required this.reportSignature,
    required this.analystId,
    required this.queuedAt,
  });

  factory LegalAidHandoffEnvelope.fromHandoff(LegalAidHandoff h) =>
      LegalAidHandoffEnvelope(
        id: h.id,
        caseNumber: h.caseNumber,
        reportSignature: h.reportSignature,
        analystId: h.analystId,
        queuedAt: h.queuedAt,
      );

  /// The strict frame: `{"v":1,"id":...,"case_number":...,"report_signature":...,"analyst_id":...,"queued_at":...}`.
  String encode() => jsonEncode({
        'v': version,
        'id': id,
        'case_number': caseNumber,
        'report_signature': reportSignature,
        'analyst_id': analystId,
        'queued_at': queuedAt.toUtc().toIso8601String(),
      });

  /// Strict decode — rejects wrong versions, missing fields, and invalid
  /// timestamps. Never partially decodes.
  factory LegalAidHandoffEnvelope.decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('handoff envelope is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('handoff envelope must be a JSON object');
    }
    final v = decoded['v'];
    if (v != version) {
      throw FormatException('unsupported handoff envelope version: $v');
    }
    final id = decoded['id'];
    final caseNumber = decoded['case_number'];
    final signature = decoded['report_signature'];
    final analystId = decoded['analyst_id'];
    final queuedAt = decoded['queued_at'];
    if (id is! String ||
        caseNumber is! String ||
        signature is! String ||
        analystId is! String ||
        queuedAt is! String) {
      throw const FormatException('handoff envelope is missing a field');
    }
    final at = DateTime.tryParse(queuedAt);
    if (at == null) {
      throw const FormatException('handoff envelope has an invalid timestamp');
    }
    return LegalAidHandoffEnvelope(
      id: id,
      caseNumber: caseNumber,
      reportSignature: signature,
      analystId: analystId,
      queuedAt: at.toUtc(),
    );
  }
}

/// Port for persisting + queueing legal-aid handoffs (Task 8.6).
///
/// Offline-first: the handoff is written to the local store IMMEDIATELY and
/// a sealed envelope is enqueued for the legal-aid webhook delivery.
abstract class LegalAidHandoffSink {
  /// Persists [handoff] locally and enqueues its sealed envelope. Returns
  /// the handoff id (the idempotency key).
  Future<String> queue(LegalAidHandoff handoff);

  /// The locally persisted handoffs (cold-start recovery snapshot).
  Future<List<LegalAidHandoff>> localHandoffs();
}
