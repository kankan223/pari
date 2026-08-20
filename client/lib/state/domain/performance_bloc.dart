import 'performance_state.dart';

/// Port for the performance monitoring BLoC (Task 12.1).
///
/// Handles metrics collection, deferred pillar loading, and performance
/// state management. No identity, no PII.
abstract class PerformanceBloc {
  /// Current state stream.
  Stream<PerformanceState> get state;

  /// Current state value.
  PerformanceState get current;

  /// Starts collecting performance metrics.
  void startMeasuring();

  /// Records the cold start time.
  void recordColdStart(int milliseconds);

  /// Records the warm start time.
  void recordWarmStart(int milliseconds);

  /// Requests loading of a deferred pillar.
  void requestPillar(String pillarId);

  /// Starts loading a deferred pillar.
  void startPillarLoading(String pillarId);

  /// Completes loading of a deferred pillar.
  void completePillarLoading(String pillarId);

  /// Refreshes metrics from the repository.
  Future<void> refresh();

  /// Disposes resources.
  void close();
}
