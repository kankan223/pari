/// A post awaiting (or already receiving) Peer Review decisions, projected
/// for the review queue UI (Task 7.6).
///
/// SECURITY CHECKPOINT (Task 7.6): carries only the non-PII author handle,
/// public civic content, the approval count, and the blinded reviewer
/// handles — never a raw identity.
class ReviewQueueEntry {
  final String postId;
  final String headline;
  final String categoryLabel;
  final String authorHandle;
  final int verifiedReviewers;

  /// Whether the local device has already reviewed this post.
  final bool reviewedByMe;

  /// Blinded reviewer display handles (e.g. `reviewer_a1b2c3`) — never raw
  /// blind hashes (SECURITY CHECKPOINT 7.6: reviewer identities blinded).
  final List<String> reviewerHandles;

  const ReviewQueueEntry({
    required this.postId,
    required this.headline,
    required this.categoryLabel,
    required this.authorHandle,
    required this.verifiedReviewers,
    required this.reviewedByMe,
    required this.reviewerHandles,
  });

  bool get consensusReached => verifiedReviewers >= 3;
}

/// Lifecycle of the review queue.
enum LedgerReviewStatus { loading, loaded, error }

/// Immutable BLoC state for the Peer Review Gate queue (Task 7.6).
class LedgerReviewState {
  final LedgerReviewStatus status;

  /// The posts currently in review (or shadow queue), newest first.
  final List<ReviewQueueEntry> queue;

  /// Number of posts in the Shadow Queue (FR-L3 teaser).
  final int shadowQueueCount;

  const LedgerReviewState({
    this.status = LedgerReviewStatus.loading,
    this.queue = const [],
    this.shadowQueueCount = 0,
  });

  bool get hasLoaded => status != LedgerReviewStatus.loading;

  LedgerReviewState copyWith({
    LedgerReviewStatus? status,
    List<ReviewQueueEntry>? queue,
    int? shadowQueueCount,
  }) =>
      LedgerReviewState(
        status: status ?? this.status,
        queue: queue ?? this.queue,
        shadowQueueCount: shadowQueueCount ?? this.shadowQueueCount,
      );
}
