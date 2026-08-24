import 'local_storage.dart';

/// Stub implementation for non-web platforms.
/// Data is not persisted — lives in memory only.
class StubLocalStorage implements LocalStorage {
  final _store = <String, String>{};

  @override
  String? getItem(String key) => _store[key];

  @override
  void setItem(String key, String value) => _store[key] = value;

  @override
  void removeItem(String key) => _store.remove(key);
}

LocalStorage createLocalStorage() => StubLocalStorage();
