import '../domain/cache_entry.dart';
import '../domain/karma_cache.dart';
import '../domain/non_sensitive_store.dart';

/// Karma score cache backed by a [NonSensitiveStore] (data layer, Task 3.6).
///
/// Entries are stored as timestamped [CacheEntry] JSON. Reads lazily
/// invalidate: an entry that has aged past [KarmaCache.ttl] is removed and
/// treated as absent, so a stale score can never surface.
///
/// The clock is injectable so the 5-minute TTL logic is fully unit-testable
/// without wall-clock dependence.
class HiveKarmaCache implements KarmaCache {
  final NonSensitiveStore _store;
  final DateTime Function() _now;
  final Duration _ttl;

  HiveKarmaCache({
    required NonSensitiveStore store,
    DateTime Function()? now,
    Duration ttl = KarmaCache.ttl,
  })  : _store = store,
        _now = now ?? DateTime.now,
        _ttl = ttl;

  @override
  Future<String?> readKarma(String key) async {
    final raw = await _store.read(_entryKey(key));
    if (raw == null) {
      return null;
    }
    final entry = CacheEntry.decode(raw);
    if (entry == null) {
      await _store.delete(_entryKey(key));
      return null;
    }
    if (entry.isExpiredAt(_now(), _ttl)) {
      await _store.delete(_entryKey(key));
      return null;
    }
    return entry.value;
  }

  @override
  Future<void> writeKarma(String key, String value) async {
    await _store.write(
      _entryKey(key),
      CacheEntry(value: value, storedAt: _now()).encode(),
    );
  }

  @override
  Future<bool> isFresh(String key) async {
    final raw = await _store.read(_entryKey(key));
    if (raw == null) {
      return false;
    }
    final entry = CacheEntry.decode(raw);
    return entry != null && !entry.isExpiredAt(_now(), _ttl);
  }

  @override
  Future<void> invalidate(String key) => _store.delete(_entryKey(key));

  @override
  Future<void> invalidateAll() => _store.clear();

  static String _entryKey(String key) => 'karma.$key';
}
