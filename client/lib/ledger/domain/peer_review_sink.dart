import 'peer_review.dart';

/// Persistence seam for Peer Review decisions (Task 7.6).
///
/// The UI reviews through the BLoC; the BLoC hands a [PeerReviewSubmission]
/// to this port. The production implementation persists the decision
/// locally FIRST (offline-first) and enqueues the sealed envelope through
/// the offline sync queue; tests use in-memory implementations.
///
/// SECURITY CHECKPOINT (Task 7.6): decisions are never persisted or logged
/// in a way that ties them to identity — the sink receives only the public
/// post id + decision code and seals it at rest.
abstract class PeerReviewSink {
  /// Records [submission] locally (offline-first). Returns the local id.
  Future<String> save(PeerReviewSubmission submission);

  /// Every locally-recorded decision (recovery snapshot for cold starts).
  Future<List<PeerReviewRecord>> localDecisions();
}
