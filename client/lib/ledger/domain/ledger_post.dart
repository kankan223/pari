import 'ledger_category.dart';
import 'ledger_vote.dart';

/// Lifecycle status of a Ledger post (PRD §6.5).
enum LedgerPostStatus {
  /// Live on the feed.
  published,

  /// In the Peer Review Gate (karma-gated trust threshold, FR-L4).
  peerReview,

  /// In the Shadow Queue (new accounts under 96h, FR-L3).
  shadowQueue;

  String get wireName => switch (this) {
        LedgerPostStatus.published => 'published',
        LedgerPostStatus.peerReview => 'peer_review',
        LedgerPostStatus.shadowQueue => 'shadow_queue',
      };

  static LedgerPostStatus fromWireName(String name) => switch (name) {
        'published' => LedgerPostStatus.published,
        'peer_review' => LedgerPostStatus.peerReview,
        'shadow_queue' => LedgerPostStatus.shadowQueue,
        _ => throw ArgumentError('Unknown ledger post status: $name'),
      };
}

/// A Ledger post (domain entity, Task 7.1).
///
/// Mirrors the post data model (PRD §6.4): exactly one [pinCode] and one
/// [category] per post (FR-L1).
///
/// SECURITY CONTRACT: [authorHandle] is a NON-PII display handle (e.g. the
/// derived `formatPeerHandle`-style handle or a remembered public username)
/// — NEVER a raw phone number, NEVER a blind hash, NEVER a real name. The
/// post body is public civic content by design (the Ledger is a public
/// pillar), but identity fields remain anonymous.
class LedgerPost {
  final String id;
  final LedgerCategory category;
  final String pinCode;

  /// Coarse district / Assembly-constituency name (public civic info,
  /// Task 7.3). The dynamic-radius feed falls back to same-district posts
  /// when the local pin is sparse. Null = not eligible for expansion.
  final String? district;

  final String headline;
  final String body;

  /// Non-PII display handle of the author (never a raw identifier).
  final String authorHandle;

  final int voteCount;
  final int commentCount;

  /// The LOCAL device's own vote on this post (Task 7.5) — drives the
  /// active state of the vote bar and the toggle semantics. This is a
  /// per-device aggregate direction, never a per-identity marker in the
  /// feed (SECURITY CHECKPOINT 7.5: the stored direction is an opaque
  /// aggregate; identity stays server-side).
  final LedgerVoteDirection myVote;

  /// Number of Peer Review Gate approvals (0..3). [verifiedReviewers] == 3
  /// renders the `[✓ Verified — 3/3]` badge (DESIGN.md §7.2).
  final int verifiedReviewers;

  final LedgerPostStatus status;
  final DateTime createdAt;

  const LedgerPost({
    required this.id,
    required this.category,
    required this.pinCode,
    this.district,
    required this.headline,
    required this.body,
    required this.authorHandle,
    this.voteCount = 0,
    this.commentCount = 0,
    this.myVote = LedgerVoteDirection.none,
    this.verifiedReviewers = 0,
    this.status = LedgerPostStatus.published,
    required this.createdAt,
  });

  LedgerPost copyWith({
    int? voteCount,
    int? commentCount,
    LedgerVoteDirection? myVote,
    int? verifiedReviewers,
    LedgerPostStatus? status,
  }) =>
      LedgerPost(
        id: id,
        category: category,
        pinCode: pinCode,
        district: district,
        headline: headline,
        body: body,
        authorHandle: authorHandle,
        voteCount: voteCount ?? this.voteCount,
        commentCount: commentCount ?? this.commentCount,
        myVote: myVote ?? this.myVote,
        verifiedReviewers: verifiedReviewers ?? this.verifiedReviewers,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}
