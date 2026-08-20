/// Represents a database shard for horizontal scaling (Task 12.4).
///
/// Each shard is identified by a pin-code prefix (first 2 digits of the
/// 6-digit Indian pin code). The prefix maps to a regional data center.
class Shard {
  /// Shard identifier (e.g., 'shard_11', 'shard_40').
  final String id;

  /// Pin-code prefix this shard handles (e.g., '11', '40').
  final String pinPrefix;

  /// Human-readable region name (e.g., 'Delhi NCR', 'Mumbai').
  final String region;

  /// Whether this shard is currently healthy.
  final bool healthy;

  /// Current load factor (0.0 to 1.0, where 1.0 = fully loaded).
  final double loadFactor;

  /// Average response time in milliseconds.
  final int avgResponseTimeMs;

  const Shard({
    required this.id,
    required this.pinPrefix,
    required this.region,
    this.healthy = true,
    this.loadFactor = 0.0,
    this.avgResponseTimeMs = 0,
  });

  /// Creates a copy with updated values.
  Shard copyWith({
    bool? healthy,
    double? loadFactor,
    int? avgResponseTimeMs,
  }) {
    return Shard(
      id: id,
      pinPrefix: pinPrefix,
      region: region,
      healthy: healthy ?? this.healthy,
      loadFactor: loadFactor ?? this.loadFactor,
      avgResponseTimeMs: avgResponseTimeMs ?? this.avgResponseTimeMs,
    );
  }

  /// Whether this shard can accept new requests.
  bool get canAcceptRequests => healthy && loadFactor < 0.9;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Shard &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          pinPrefix == other.pinPrefix;

  @override
  int get hashCode => Object.hash(id, pinPrefix);
}

/// Routes requests to the appropriate shard based on pin-code prefix.
///
/// Implements pin-code prefix-based sharding (MASTER_PLAN §12.4).
/// The first 2 digits of the 6-digit pin code determine the shard.
class ShardRouter {
  final Map<String, Shard> _shards;

  ShardRouter({Map<String, Shard>? shards}) : _shards = shards ?? defaultShards;

  /// Returns the shard for a given pin code.
  Shard routeByPinCode(String pinCode) {
    if (pinCode.length < 2) {
      throw ArgumentError('Pin code must be at least 2 digits');
    }
    final prefix = pinCode.substring(0, 2);
    return _shards[prefix] ?? _shards['default']!;
  }

  /// Returns the shard for a given pin-code prefix.
  Shard routeByPrefix(String prefix) {
    return _shards[prefix] ?? _shards['default']!;
  }

  /// Returns all healthy shards.
  List<Shard> get healthyShards =>
      _shards.values.where((s) => s.healthy).toList(growable: false);

  /// Returns the least-loaded healthy shard.
  Shard? get leastLoadedShard {
    final healthy = healthyShards;
    if (healthy.isEmpty) return null;
    healthy.sort((a, b) => a.loadFactor.compareTo(b.loadFactor));
    return healthy.first;
  }

  /// Returns all shards sorted by load factor.
  List<Shard> get shardsByLoad {
    final sorted = List<Shard>.from(_shards.values);
    sorted.sort((a, b) => a.loadFactor.compareTo(b.loadFactor));
    return sorted;
  }

  /// Returns the total number of shards.
  int get shardCount => _shards.length;

  /// Returns the average load factor across all healthy shards.
  double get avgLoadFactor {
    final healthy = healthyShards;
    if (healthy.isEmpty) return 0;
    return healthy.fold(0.0, (sum, s) => sum + s.loadFactor) / healthy.length;
  }
}

/// Default shard configuration for Indian pin-code regions (Task 12.4).
const Map<String, Shard> defaultShards = {
  '11': Shard(id: 'shard_11', pinPrefix: '11', region: 'Delhi NCR'),
  '20': Shard(id: 'shard_20', pinPrefix: '20', region: 'Uttar Pradesh'),
  '30': Shard(id: 'shard_30', pinPrefix: '30', region: 'Rajasthan'),
  '40': Shard(id: 'shard_40', pinPrefix: '40', region: 'Mumbai'),
  '50': Shard(id: 'shard_50', pinPrefix: '50', region: 'Telangana'),
  '60': Shard(id: 'shard_60', pinPrefix: '60', region: 'Tamil Nadu'),
  '70': Shard(id: 'shard_70', pinPrefix: '70', region: 'West Bengal'),
  '80': Shard(id: 'shard_80', pinPrefix: '80', region: 'Bihar/Jharkhand'),
  '90': Shard(id: 'shard_90', pinPrefix: '90', region: 'Punjab/Haryana'),
  'default': Shard(id: 'shard_default', pinPrefix: '00', region: 'Default'),
};
