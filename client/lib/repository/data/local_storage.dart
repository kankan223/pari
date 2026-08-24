import 'local_storage_stub.dart'
    if (dart.library.html) 'local_storage_web.dart';

/// Abstract interface for key-value persistence.
///
/// On web: backed by browser `window.localStorage`.
/// On non-web: no-op stub (data lives in memory only).
///
/// Used by [_MemStore] to persist messages and conversations across
/// page refreshes on web.
abstract class LocalStorage {
  String? getItem(String key);
  void setItem(String key, String value);
  void removeItem(String key);

  /// Factory constructor that returns the platform-specific implementation.
  factory LocalStorage() => createLocalStorage();
}
