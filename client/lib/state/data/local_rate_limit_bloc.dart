import 'dart:async';

import '../../rate_limit/domain/rate_limit_bucket.dart';
import '../../rate_limit/domain/rate_limit_policy.dart';
import '../../rate_limit/domain/rate_limit_repository.dart';
import '../domain/rate_limit_bloc.dart';
import '../domain/rate_limit_state.dart';

/// Local implementation of [RateLimitBloc] (Task 11.3).
///
/// Backed by [RateLimitRepository] (in-memory for the harness,
/// SQLCipher for production). Monotonic sequence guards prevent stale
/// late-subscriber updates.
///
/// SECURITY CHECKPOINT (11.3):
/// - Repository failures map to a generic, payload-free
///   [RateLimitState] error — never leaking stack traces, database
///   errors, or PII.
/// - [refresh] reads only rate limit buckets and abuse events from the store.
class LocalRateLimitBloc implements RateLimitBloc {
  final RateLimitRepository _repository;

  final _controller = StreamController<RateLimitState>.broadcast();
  var _seq = 0;
  var _current = const RateLimitState();

  LocalRateLimitBloc({required RateLimitRepository repository})
      : _repository = repository;

  @override
  Stream<RateLimitState> get state => _controller.stream;

  @override
  RateLimitState get current => _current;

  @override
  Future<void> refresh() async {
    final seq = ++_seq;
    _emit(const RateLimitState(phase: RateLimitPhase.loading));

    try {
      final buckets = <String, RateLimitBucket>{};
      for (final policy in RateLimitPolicy.values) {
        final bucket = await _repository.getBucket(policy);
        buckets[policy.name] = bucket;
      }

      final abuseEvents = await _repository.getAbuseEvents();
      final totalEvents = await _repository.getAbuseEventCount();

      if (seq != _seq) return; // stale

      _emit(RateLimitState(
        phase: RateLimitPhase.ready,
        buckets: buckets,
        abuseEvents: abuseEvents,
        totalAbuseEvents: totalEvents,
      ));
    } catch (_) {
      if (seq != _seq) return;
      _emit(const RateLimitState(
        phase: RateLimitPhase.error,
        errorMessage: 'Unable to load rate limit data',
      ));
    }
  }

  @override
  Future<bool> recordRequest(RateLimitPolicy policy) async {
    final seq = ++_seq;

    try {
      final updated = await _repository.recordRequest(policy);

      if (seq != _seq) return false;

      final newBuckets = Map<String, RateLimitBucket>.from(_current.buckets);
      newBuckets[policy.name] = updated;

      _emit(RateLimitState(
        phase: RateLimitPhase.ready,
        buckets: newBuckets,
        abuseEvents: _current.abuseEvents,
        totalAbuseEvents: _current.totalAbuseEvents,
      ));

      return updated.isLimitReached;
    } catch (_) {
      if (seq != _seq) return false;
      _emit(const RateLimitState(
        phase: RateLimitPhase.error,
        errorMessage: 'Unable to record request',
      ));
      return false;
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void _emit(RateLimitState state) {
    _current = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}
