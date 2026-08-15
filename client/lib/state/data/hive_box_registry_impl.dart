import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../domain/hive_box_key_provider.dart';
import '../domain/hive_box_registry.dart';
import '../domain/karma_cache.dart';
import '../domain/non_sensitive_store.dart';
import 'hive_karma_cache.dart';
import 'hive_non_sensitive_store.dart';

/// Hive-backed [HiveBoxRegistry] (data layer, Task 3.6).
///
/// Initialization:
/// - Opens the three canonical NON-SENSITIVE boxes (`ledger_drafts`,
///   `academy_progress`, `karma_cache`) WITHOUT encryption — the
///   [NonSensitiveGuard] enforced by [HiveNonSensitiveStore] rejects any
///   sensitive payload written to them.
/// - Any box opened via [openSensitiveBox] is opened WITH a [HiveAesCipher]
///   whose 32-byte key comes from the injected [HiveBoxKeyProvider] (throws
///   if no key is registered).
class HiveBoxRegistryImpl implements HiveBoxRegistry {
  final HiveInterface _hive;
  final String _path;
  final HiveBoxKeyProvider _keyProvider;
  final DateTime Function() _now;

  final Map<String, NonSensitiveStore> _stores = {};
  final List<Box<String>> _openBoxes = [];
  bool _initialized = false;

  HiveBoxRegistryImpl({
    required HiveInterface hive,
    required String path,
    required HiveBoxKeyProvider keyProvider,
    DateTime Function()? now,
  })  : _hive = hive,
        _path = path,
        _keyProvider = keyProvider,
        _now = now ?? DateTime.now;

  @override
  bool get isInitialized => _initialized;

  @override
  NonSensitiveStore get ledgerDrafts =>
      _requireStore(HiveBoxNames.ledgerDrafts);

  @override
  NonSensitiveStore get academyProgress =>
      _requireStore(HiveBoxNames.academyProgress);

  @override
  KarmaCache get karmaCache =>
      HiveKarmaCache(store: _requireStore(HiveBoxNames.karmaCache), now: _now);

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _hive.init(_path);
    // Canonical boxes are NON-SENSITIVE → opened without encryption.
    await _open(HiveBoxNames.ledgerDrafts, sensitive: false);
    await _open(HiveBoxNames.academyProgress, sensitive: false);
    await _open(HiveBoxNames.karmaCache, sensitive: false);
    _initialized = true;
  }

  @override
  Future<NonSensitiveStore> openSensitiveBox(String name) async {
    _ensureInitialized();
    final existing = _stores[name];
    if (existing != null) {
      return existing;
    }
    return _open(name, sensitive: true);
  }

  @override
  Future<void> close() async {
    for (final box in _openBoxes) {
      await box.close();
    }
    _openBoxes.clear();
    _stores.clear();
    _initialized = false;
  }

  Future<NonSensitiveStore> _open(String name,
      {required bool sensitive}) async {
    final Uint8List? key = sensitive ? await _keyProvider.keyFor(name) : null;
    if (sensitive && key == null) {
      throw StateError(
        'No encryption key registered for sensitive Hive box "$name" — '
        'sensitive boxes must never be opened unencrypted',
      );
    }
    final box = await _hive.openBox<String>(
      name,
      encryptionCipher: key == null ? null : HiveAesCipher(key),
    );
    _openBoxes.add(box);
    final store = HiveNonSensitiveStore(box);
    _stores[name] = store;
    return store;
  }

  NonSensitiveStore _requireStore(String name) {
    _ensureInitialized();
    final store = _stores[name];
    if (store == null) {
      throw StateError('Hive box "$name" is not open');
    }
    return store;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
          'HiveBoxRegistry is not initialized — call initialize() first');
    }
  }
}
