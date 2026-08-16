/// A reviewer's decision on a Ledger post inside the Peer Review Gate
/// (Task 7.6, FR-L4).
///
/// SECURITY CONTRACT: a decision carries ONLY the public post id + a
/// decision code — NO reviewer identity, NO PII. The reviewer is a blinded
/// participant (the wire frame never carries who reviewed).
enum PeerReviewDecision {
  /// The reviewer verified the post — counts toward the 3/3 consensus.
  approved,

  /// The reviewer rejected the post — it stays in review (no approval
  /// counted); the decision is still recorded and synced.
  rejected,

  /// The reviewer flagged the post for moderation — the decision is
  /// recorded and synced; server-side moderation acts on the flag.
  flagged;

  /// Stable wire identifier (server contract, never rendered).
  String get wireName => switch (this) {
        PeerReviewDecision.approved => 'approved',
        PeerReviewDecision.rejected => 'rejected',
        PeerReviewDecision.flagged => 'flagged',
      };

  /// Parses a wire name, throwing [ArgumentError] for unknown values
  /// (strict bounds — a server can never smuggle an unknown decision in).
  static PeerReviewDecision fromWireName(String name) => switch (name) {
        'approved' => PeerReviewDecision.approved,
        'rejected' => PeerReviewDecision.rejected,
        'flagged' => PeerReviewDecision.flagged,
        _ => throw ArgumentError('Unknown peer review decision: $name'),
      };
}

/// A peer review action cast by the local device (Task 7.6).
///
/// SECURITY CONTRACT: carries ONLY the public post id + a decision code —
/// the reviewer is the device itself; identity never rides in the payload
/// (the sync transport authenticates the reviewer server-side).
class PeerReviewSubmission {
  final String postId;
  final PeerReviewDecision decision;

  const PeerReviewSubmission({
    required this.postId,
    required this.decision,
  });
}

/// A durable local record of a peer review action (Task 7.6).
///
/// SECURITY CONTRACT: post id + decision + timestamp ONLY — no reviewer
/// identity, no PII. The row lives inside the SQLCipher-encrypted database;
/// the queued copy is sealed by the queue cipher.
class PeerReviewRecord {
  final String postId;
  final PeerReviewDecision decision;
  final DateTime reviewedAt;

  const PeerReviewRecord({
    required this.postId,
    required this.decision,
    required this.reviewedAt,
  });
}

/// A blinded reviewer verification (Task 7.6).
///
/// [reviewerHandle] is a NON-PII derived display handle (e.g. `reviewer_`
/// + a short hex digest) — NEVER a raw blind hash, NEVER a phone, NEVER a
/// name. It exists so the UI can show *a reviewer acted* without ever
/// revealing *who* (SECURITY CHECKPOINT 7.6: reviewer identities blinded).
class ReviewerVerification {
  final String postId;
  final String reviewerHandle;
  final PeerReviewDecision decision;
  final DateTime reviewedAt;

  const ReviewerVerification({
    required this.postId,
    required this.reviewerHandle,
    required this.decision,
    required this.reviewedAt,
  });
}
