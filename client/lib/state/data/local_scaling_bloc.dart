import 'dart:async';

import '../../scaling/data/in_memory_scaling_repository.dart';
import '../../scaling/domain/load_test_scenario.dart';
import '../domain/scaling_bloc.dart';
import '../domain/scaling_state.dart';

/// Local implementation of [ScalingBloc] (Task 12.4).
///
/// Manages load test execution and scaling metrics collection.
/// Uses monotonic sequence guards to prevent stale state updates.
class LocalScalingBloc implements ScalingBloc {
  final InMemoryScalingRepository _repository;

  final _controller = StreamController<ScalingState>.broadcast();
  var _sequence = 0;
  var _current = const ScalingState();
  bool _closed = false;

  LocalScalingBloc({required InMemoryScalingRepository repository})
      : _repository = repository;

  @override
  Stream<ScalingState> get state => _controller.stream;

  @override
  ScalingState get current => _current;

  @override
  void startMeasuring() {
    if (_closed) return;
    final seq = ++_sequence;
    _current = _current.copyWith(phase: ScalingPhase.idle);
    _emit();
    unawaited(_loadMetrics(seq));
  }

  @override
  Future<void> runLoadTest(LoadTestScenario scenario) async {
    if (_closed) return;
    final seq = ++_sequence;
    _current = _current.copyWith(
      phase: ScalingPhase.running,
      currentScenario: scenario,
    );
    _emit();

    try {
      final metrics = await _repository.runLoadTest(scenario);
      if (_closed || seq != _sequence) return;
      _current = _current.copyWith(
        phase: ScalingPhase.ready,
        metrics: metrics,
      );
      _emit();
    } catch (e) {
      if (_closed || seq != _sequence) return;
      _current = _current.copyWith(
        phase: ScalingPhase.error,
        errorMessage: 'Load test failed: $e',
      );
      _emit();
    }
  }

  @override
  void recordRequest({
    required bool success,
    required int latencyMs,
    required String shardId,
  }) {
    if (_closed) return;
    unawaited(_repository.recordRequest(
      success: success,
      latencyMs: latencyMs,
      shardId: shardId,
    ));
    // Update local state optimistically
    final old = _current.metrics;
    final total = old.totalRequests + 1;
    final successful =
        success ? old.successfulRequests + 1 : old.successfulRequests;
    final failed = !success ? old.failedRequests + 1 : old.failedRequests;
    final totalTime = old.avgLatencyMs * old.totalRequests + latencyMs;
    final avgLatency = total > 0 ? (totalTime ~/ total) : 0;

    _current = _current.copyWith(
      metrics: old.copyWith(
        totalRequests: total,
        successfulRequests: successful,
        failedRequests: failed,
        avgLatencyMs: avgLatency,
      ),
    );
    _emit();
  }

  @override
  void recordConnection({required bool opened}) {
    if (_closed) return;
    unawaited(_repository.recordConnection(opened: opened));
    final old = _current.metrics;
    final newCount = opened
        ? old.activeConnections + 1
        : (old.activeConnections - 1).clamp(0, old.activeConnections);
    final peak =
        newCount > old.peakConnections ? newCount : old.peakConnections;

    _current = _current.copyWith(
      metrics: old.copyWith(
        activeConnections: newCount,
        peakConnections: peak,
      ),
    );
    _emit();
  }

  @override
  Future<void> refresh() async {
    if (_closed) return;
    final seq = ++_sequence;
    await _loadMetrics(seq);
  }

  @override
  void close() {
    _closed = true;
    _controller.close();
  }

  Future<void> _loadMetrics(int seq) async {
    try {
      final metrics = await _repository.getMetrics();
      if (_closed || seq != _sequence) return;
      _current = _current.copyWith(
        phase: ScalingPhase.ready,
        metrics: metrics,
      );
      _emit();
    } catch (e) {
      if (_closed || seq != _sequence) return;
      _current = _current.copyWith(
        phase: ScalingPhase.error,
        errorMessage: 'Failed to load scaling metrics',
      );
      _emit();
    }
  }

  void _emit() {
    if (!_closed && !_controller.isClosed) {
      _controller.add(_current);
    }
  }
}
