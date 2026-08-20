import '../domain/startup_optimizer.dart';

/// In-memory startup optimizer for managing deferred pillar loading (Task 12.1).
///
/// Tracks pillar states and loading order for code-splitting optimization.
class InMemoryStartupOptimizer {
  final Map<String, DeferredPillar> _pillars = {};

  /// All registered pillars.
  List<DeferredPillar> get pillars => _pillars.values.toList(growable: false);

  /// Pillars that are ready.
  List<DeferredPillar> get readyPillars =>
      _pillars.values.where((p) => p.isReady).toList(growable: false);

  /// Pillars that are currently loading.
  List<DeferredPillar> get loadingPillars => _pillars.values
      .where((p) => p.state == DeferredPillarState.loading)
      .toList(growable: false);

  /// Registers a new pillar for deferred loading.
  void register(DeferredPillar pillar) {
    _pillars[pillar.pillarId] = pillar;
  }

  /// Requests loading of a pillar (marks as requested).
  void requestPillar(String pillarId) {
    final existing = _pillars[pillarId];
    if (existing != null) {
      _pillars[pillarId] = existing.copyWith(requested: true);
    }
  }

  /// Starts loading a pillar (marks as loading).
  void startLoading(String pillarId) {
    final existing = _pillars[pillarId];
    if (existing != null) {
      _pillars[pillarId] = existing.copyWith(
        state: DeferredPillarState.loading,
        loadingStartedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  /// Completes loading of a pillar (marks as ready).
  void completeLoading(String pillarId) {
    final existing = _pillars[pillarId];
    if (existing != null) {
      _pillars[pillarId] = existing.copyWith(
        state: DeferredPillarState.ready,
        loadingCompletedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  /// Marks a pillar as failed.
  void markFailed(String pillarId) {
    final existing = _pillars[pillarId];
    if (existing != null) {
      _pillars[pillarId] = existing.copyWith(
        state: DeferredPillarState.failed,
      );
    }
  }

  /// Returns pillars sorted by priority (lower number = higher priority).
  List<DeferredPillar> get pillarsByPriority {
    final sorted = List<DeferredPillar>.from(_pillars.values);
    sorted.sort((a, b) => a.priority.compareTo(b.priority));
    return sorted;
  }

  /// Returns only requested pillars that haven't started loading.
  List<DeferredPillar> get pendingRequestedPillars => _pillars.values
      .where((p) => p.requested && p.state == DeferredPillarState.notStarted)
      .toList(growable: false);

  /// Resets all pillar states to notStarted.
  void reset() {
    for (final id in _pillars.keys) {
      final p = _pillars[id]!;
      _pillars[id] = DeferredPillar(
        pillarId: p.pillarId,
        displayName: p.displayName,
        priority: p.priority,
        requested: p.requested,
      );
    }
  }

  /// Gets a specific pillar by ID.
  DeferredPillar? getPillar(String pillarId) => _pillars[pillarId];
}
