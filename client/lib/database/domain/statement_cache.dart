/// Configuration for SQL statement caching (Task 12.2).
///
/// Controls how many prepared statements are cached and when they are
/// evicted. All values are pure integers — no identity, no PII.
class StatementCacheConfig {
  /// Maximum number of cached prepared statements.
  final int maxCacheSize;

  /// Whether to enable WAL mode for better concurrent read performance.
  final bool enableWalMode;

  /// Page size for the database (must be power of 2, 512–65536).
  final int pageSize;

  /// Number of pages for the memory-mapped I/O region (0 = disabled).
  final int mmapSize;

  /// Cache size in pages for the database (negative = KiB).
  final int cacheSizePages;

  /// Synchronous mode: 0=OFF, 1=NORMAL, 2=FULL, 3=EXTRA.
  final int synchronousMode;

  /// Journal mode: WAL, DELETE, TRUNCATE, MEMORY, OFF.
  final String journalMode;

  /// Temp store: 0=DEFAULT, 1=FILE, 2=MEMORY.
  final int tempStore;

  const StatementCacheConfig({
    this.maxCacheSize = 50,
    this.enableWalMode = true,
    this.pageSize = 4096,
    this.mmapSize = 268435456, // 256 MB
    this.cacheSizePages = -8000, // 8 MB
    this.synchronousMode = 1, // NORMAL (WAL safe)
    this.journalMode = 'WAL',
    this.tempStore = 2, // MEMORY
  });

  /// Conservative config for low-memory devices.
  const StatementCacheConfig.conservative()
      : maxCacheSize = 20,
        enableWalMode = true,
        pageSize = 4096,
        mmapSize = 0,
        cacheSizePages = -4000, // 4 MB
        synchronousMode = 1,
        journalMode = 'WAL',
        tempStore = 2;

  /// Aggressive config for high-end devices.
  const StatementCacheConfig.aggressive()
      : maxCacheSize = 100,
        enableWalMode = true,
        pageSize = 4096,
        mmapSize = 536870912, // 512 MB
        cacheSizePages = -16000, // 16 MB
        synchronousMode = 1,
        journalMode = 'WAL',
        tempStore = 2;
}

/// Statistics about the statement cache (Task 12.2).
class StatementCacheStats {
  /// Number of cache hits.
  final int hits;

  /// Number of cache misses.
  final int misses;

  /// Number of evictions (statements removed from cache).
  final int evictions;

  /// Current number of cached statements.
  final int cachedCount;

  /// Maximum cache size.
  final int maxSize;

  const StatementCacheStats({
    this.hits = 0,
    this.misses = 0,
    this.evictions = 0,
    this.cachedCount = 0,
    this.maxSize = 50,
  });

  /// Hit ratio (0.0 to 1.0, or NaN if no requests).
  double get hitRatio =>
      (hits + misses) > 0 ? hits / (hits + misses) : double.nan;

  /// Creates a copy with updated values.
  StatementCacheStats copyWith({
    int? hits,
    int? misses,
    int? evictions,
    int? cachedCount,
    int? maxSize,
  }) {
    return StatementCacheStats(
      hits: hits ?? this.hits,
      misses: misses ?? this.misses,
      evictions: evictions ?? this.evictions,
      cachedCount: cachedCount ?? this.cachedCount,
      maxSize: maxSize ?? this.maxSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatementCacheStats &&
          runtimeType == other.runtimeType &&
          hits == other.hits &&
          misses == other.misses &&
          evictions == other.evictions &&
          cachedCount == other.cachedCount &&
          maxSize == other.maxSize;

  @override
  int get hashCode =>
      Object.hash(hits, misses, evictions, cachedCount, maxSize);
}

/// Port for managing SQL statement caching and connection optimization.
///
/// Implementations optimize SQLCipher connection performance through
/// statement caching, WAL mode, and connection parameter tuning.
/// No identity, no PII.
abstract class StatementCachePort {
  /// Applies the given cache configuration to the database connection.
  Future<void> applyConfig(StatementCacheConfig config);

  /// Returns current cache statistics.
  Future<StatementCacheStats> getStats();

  /// Clears the statement cache (e.g., after schema migration).
  Future<void> clearCache();

  /// Runs PRAGMA optimize to rebuild query plans.
  Future<void> optimizeQueryPlans();

  /// Returns the current database page count (for monitoring).
  Future<int> getPageCount();

  /// Returns the current database page size.
  Future<int> getPageSize();
}
