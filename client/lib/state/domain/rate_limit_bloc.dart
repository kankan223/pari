import '../../rate_limit/domain/rate_limit_policy.dart';
import 'rate_limit_state.dart';

/// BLoC for the Rate Limiting & Abuse Prevention system (Task 11.3).
///
/// The UI binds to [state] and calls [refresh] / [recordRequest] — it
/// never talks to the rate limit repository directly.
///
/// SECURITY CHECKPOINT (11.3): [RateLimitState] carries only fixed policy
/// labels, trigger labels, severity labels, and integer counts. No phone
/// number, no blind hash, no identity can appear in state; error states
/// carry no payload at all.
abstract class RateLimitBloc {
  /// Stream of rate limit states (idle → loading → ready | error).
  Stream<RateLimitState> get state;

  /// The current state (for late subscribers).
  RateLimitState get current;

  /// Loads rate limit buckets and abuse events.
  Future<void> refresh();

  /// Records a request for the given [policy] and returns the updated bucket.
  /// If the limit is reached, the bucket will be in cooldown.
  Future<bool> recordRequest(RateLimitPolicy policy);

  /// Releases resources.
  Future<void> close();
}
