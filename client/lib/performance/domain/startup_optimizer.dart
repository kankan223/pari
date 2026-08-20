/// Represents the initialization state of a deferred pillar (Task 12.1).
///
/// Pillars are loaded on-demand rather than at startup to reduce cold start
/// time. Each pillar has a priority and loading state.
enum DeferredPillarState {
  /// Not yet requested.
  notStarted,

  /// Currently initializing.
  loading,

  /// Initialization complete, pillar is available.
  ready,

  /// Initialization failed.
  failed,
}

/// A deferred pillar that can be loaded after startup (Task 12.1).
///
/// Contains no identity, no PII — only a pillar identifier and state.
class DeferredPillar {
  /// Unique pillar identifier (e.g., 'vault', 'ledger', 'academy', 'warroom').
  final String pillarId;

  /// Display name for the pillar.
  final String displayName;

  /// Current loading state.
  final DeferredPillarState state;

  /// Priority for loading order (lower = higher priority).
  final int priority;

  /// Whether this pillar has been requested by the user.
  final bool requested;

  /// Timestamp when loading started (milliseconds since epoch).
  final int? loadingStartedAt;

  /// Timestamp when loading completed (milliseconds since epoch).
  final int? loadingCompletedAt;

  const DeferredPillar({
    required this.pillarId,
    required this.displayName,
    this.state = DeferredPillarState.notStarted,
    this.priority = 0,
    this.requested = false,
    this.loadingStartedAt,
    this.loadingCompletedAt,
  });

  /// Creates a copy with updated values.
  DeferredPillar copyWith({
    DeferredPillarState? state,
    bool? requested,
    int? loadingStartedAt,
    int? loadingCompletedAt,
  }) {
    return DeferredPillar(
      pillarId: pillarId,
      displayName: displayName,
      state: state ?? this.state,
      priority: priority,
      requested: requested ?? this.requested,
      loadingStartedAt: loadingStartedAt ?? this.loadingStartedAt,
      loadingCompletedAt: loadingCompletedAt ?? this.loadingCompletedAt,
    );
  }

  /// Whether this pillar is ready for use.
  bool get isReady => state == DeferredPillarState.ready;

  /// Whether loading duration can be computed.
  bool get hasLoadDuration =>
      loadingStartedAt != null && loadingCompletedAt != null;

  /// Loading duration in milliseconds, or null if not available.
  int? get loadDurationMs =>
      hasLoadDuration ? loadingCompletedAt! - loadingStartedAt! : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeferredPillar &&
          runtimeType == other.runtimeType &&
          pillarId == other.pillarId &&
          state == other.state;

  @override
  int get hashCode => Object.hash(pillarId, state);
}
