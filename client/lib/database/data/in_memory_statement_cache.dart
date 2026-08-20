import '../domain/statement_cache.dart';

/// In-memory implementation of [StatementCachePort] for tests (Task 12.2).
///
/// Tracks cache operations and statistics without an actual database.
class InMemoryStatementCache implements StatementCachePort {
  var _stats = const StatementCacheStats();
  final int _pageSize = 4096;
  final _appliedConfigs = <StatementCacheConfig>[];

  /// History of applied configs (for test verification).
  List<StatementCacheConfig> get appliedConfigs =>
      List.unmodifiable(_appliedConfigs);

  /// Whether the cache has been cleared at least once.
  bool cacheWasCleared = false;

  /// Whether optimizeQueryPlans has been called.
  bool optimizeWasCalled = false;

  @override
  Future<void> applyConfig(StatementCacheConfig config) async {
    _appliedConfigs.add(config);
    _stats = _stats.copyWith(maxSize: config.maxCacheSize);
  }

  @override
  Future<StatementCacheStats> getStats() async => _stats;

  @override
  Future<void> clearCache() async {
    cacheWasCleared = true;
    _stats = _stats.copyWith(
      cachedCount: 0,
      evictions: _stats.evictions + _stats.cachedCount,
    );
  }

  @override
  Future<void> optimizeQueryPlans() async {
    optimizeWasCalled = true;
  }

  @override
  Future<int> getPageCount() async => 100;

  @override
  Future<int> getPageSize() async => _pageSize;

  /// Simulates a cache hit for testing.
  void simulateHit() {
    _stats = _stats.copyWith(hits: _stats.hits + 1);
  }

  /// Simulates a cache miss for testing.
  void simulateMiss() {
    _stats = _stats.copyWith(
      misses: _stats.misses + 1,
      cachedCount: _stats.cachedCount + 1,
    );
  }

  /// Simulates an eviction for testing.
  void simulateEviction() {
    _stats = _stats.copyWith(
      evictions: _stats.evictions + 1,
      cachedCount: (_stats.cachedCount - 1).clamp(0, _stats.maxSize),
    );
  }
}
