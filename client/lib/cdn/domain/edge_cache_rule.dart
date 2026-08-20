/// Represents an edge caching rule for a CDN asset type (Task 12.3).
///
/// Defines how different asset types are cached at the edge, including
/// TTL, cache-control headers, and invalidation policies. All values
/// are pure strings and integers — no identity, no PII.
class EdgeCacheRule {
  /// Asset type this rule applies to (e.g., 'module_video', 'module_pdf').
  final String assetType;

  /// Cache-Control header value (e.g., 'public, max-age=86400').
  final String cacheControl;

  /// TTL in seconds for the edge cache.
  final int ttlSeconds;

  /// Whether the asset can be stale-while-revalidating.
  final bool staleWhileRevalidate;

  /// Whether the asset is immutable (never changes after publish).
  final bool immutable;

  /// Optional Vary header for content negotiation.
  final String? vary;

  const EdgeCacheRule({
    required this.assetType,
    required this.cacheControl,
    required this.ttlSeconds,
    this.staleWhileRevalidate = false,
    this.immutable = false,
    this.vary,
  });

  /// Creates a rule for immutable module content (video, PDF).
  const EdgeCacheRule.immutableModule({
    required String assetType,
    int ttlSeconds = 31536000, // 1 year
  }) : this(
          assetType: assetType,
          cacheControl: 'public, max-age=$ttlSeconds, immutable',
          ttlSeconds: ttlSeconds,
          staleWhileRevalidate: false,
          immutable: true,
        );

  /// Creates a rule for mutable module metadata (titles, descriptions).
  const EdgeCacheRule.mutableMetadata({
    required String assetType,
    int ttlSeconds = 3600, // 1 hour
  }) : this(
          assetType: assetType,
          cacheControl:
              'public, max-age=$ttlSeconds, stale-while-revalidate=300',
          ttlSeconds: ttlSeconds,
          staleWhileRevalidate: true,
          immutable: false,
        );

  /// Creates a rule for API responses (short TTL).
  const EdgeCacheRule.apiResponse({
    required String assetType,
    int ttlSeconds = 60,
  }) : this(
          assetType: assetType,
          cacheControl: 'private, max-age=$ttlSeconds',
          ttlSeconds: ttlSeconds,
          staleWhileRevalidate: false,
          immutable: false,
        );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgeCacheRule &&
          runtimeType == other.runtimeType &&
          assetType == other.assetType &&
          ttlSeconds == other.ttlSeconds;

  @override
  int get hashCode => Object.hash(assetType, ttlSeconds);
}

/// Default edge caching rules for Civic Commons assets (Task 12.3).
const List<EdgeCacheRule> defaultEdgeCacheRules = [
  EdgeCacheRule.immutableModule(assetType: 'module_video'),
  EdgeCacheRule.immutableModule(assetType: 'module_pdf'),
  EdgeCacheRule.immutableModule(assetType: 'module_audio'),
  EdgeCacheRule.mutableMetadata(assetType: 'module_metadata'),
  EdgeCacheRule.mutableMetadata(assetType: 'syllabus_tree'),
  EdgeCacheRule.apiResponse(assetType: 'presigned_url'),
  EdgeCacheRule.apiResponse(assetType: 'module_manifest'),
];
