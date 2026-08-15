import '../domain/non_sensitive_guard.dart';
import '../domain/non_sensitive_store.dart';

/// In-memory [NonSensitiveStore] (data layer, Task 3.5).
///
/// Used in tests and as a bootstrap before Hive is initialized on device.
/// Enforces the [NonSensitiveGuard] defense-in-depth check on every write.
class MemoryNonSensitiveStore implements NonSensitiveStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    NonSensitiveGuard.assertNonSensitive(key, value);
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> clear() async {
    _data.clear();
  }
}
