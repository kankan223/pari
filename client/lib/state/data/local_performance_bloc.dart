import 'dart:async';

import '../../performance/data/in_memory_startup_optimizer.dart';
import '../../performance/domain/performance_repository.dart';
import '../domain/performance_bloc.dart';
import '../domain/performance_state.dart';

/// Local implementation of [PerformanceBloc] (Task 12.1).
///
/// Manages metrics collection and deferred pillar loading state.
/// Uses monotonic sequence guards to prevent stale state updates.
class LocalPerformanceBloc implements PerformanceBloc {
  final PerformanceRepository _repository;
  final InMemoryStartupOptimizer _optimizer;

  final _controller = StreamController<PerformanceState>.broadcast();
  var _sequence = 0;
  var _current = const PerformanceState();
  bool _closed = false;

  LocalPerformanceBloc({
    required PerformanceRepository repository,
    InMemoryStartupOptimizer? optimizer,
  })  : _repository = repository,
        _optimizer = optimizer ?? InMemoryStartupOptimizer();

  @override
  Stream<PerformanceState> get state => _controller.stream;

  @override
  PerformanceState get current => _current;

  @override
  void startMeasuring() {
    if (_closed) return;
    final seq = ++_sequence;
    _current = _current.copyWith(phase: PerformancePhase.measuring);
    _emit();
    unawaited(_loadMetrics(seq));
  }

  @override
  void recordColdStart(int milliseconds) {
    if (_closed) return;
    unawaited(_repository.recordColdStart(milliseconds));
    _current = _current.copyWith(
      metrics: _current.metrics.copyWith(coldStartMs: milliseconds),
    );
    _emit();
  }

  @override
  void recordWarmStart(int milliseconds) {
    if (_closed) return;
    unawaited(_repository.recordWarmStart(milliseconds));
    _current = _current.copyWith(
      metrics: _current.metrics.copyWith(warmStartMs: milliseconds),
    );
    _emit();
  }

  @override
  void requestPillar(String pillarId) {
    if (_closed) return;
    _optimizer.requestPillar(pillarId);
    _updatePillars();
  }

  @override
  void startPillarLoading(String pillarId) {
    if (_closed) return;
    _optimizer.startLoading(pillarId);
    _updatePillars();
  }

  @override
  void completePillarLoading(String pillarId) {
    if (_closed) return;
    _optimizer.completeLoading(pillarId);
    unawaited(_repository.recordDeferredLoad());
    _updatePillars();
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

  void _updatePillars() {
    _current = _current.copyWith(
      deferredPillars: _optimizer.pillars,
    );
    _emit();
  }

  Future<void> _loadMetrics(int seq) async {
    try {
      final metrics = await _repository.getMetrics();
      if (_closed || seq != _sequence) return;
      _current = _current.copyWith(
        phase: PerformancePhase.ready,
        metrics: metrics,
        deferredPillars: _optimizer.pillars,
      );
      _emit();
    } catch (e) {
      if (_closed || seq != _sequence) return;
      _current = _current.copyWith(
        phase: PerformancePhase.error,
        errorMessage: 'Failed to load metrics',
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
