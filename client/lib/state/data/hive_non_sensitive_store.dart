import 'package:hive_ce_flutter/hive_flutter.dart';

import '../domain/non_sensitive_guard.dart';
import '../domain/non_sensitive_store.dart';

/// Hive-backed [NonSensitiveStore] (data layer, Task 3.5).
///
/// Persists NON-SENSITIVE state (UI prefs, ledger drafts metadata, academy
/// progress, karma cache) into a Hive box. Sensitive data is barred by the
/// [NonSensitiveGuard] and architecturally lives only in the encrypted
/// SQLCipher database / keychain — never here.
class HiveNonSensitiveStore implements NonSensitiveStore {
  final Box<String> _box;

  HiveNonSensitiveStore(this._box);

  @override
  Future<String?> read(String key) async => _box.get(key);

  @override
  Future<void> write(String key, String value) async {
    NonSensitiveGuard.assertNonSensitive(key, value);
    await _box.put(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _box.delete(key);
  }

  @override
  Future<void> clear() async {
    await _box.clear();
  }
}
