import '../../repository/domain/entity_store.dart';
import '../domain/device_registry.dart';
import '../domain/linked_device.dart';

/// [DeviceRegistry] backed by the encrypted local [EntityStore] (data layer,
/// Task 6.5).
///
/// All reads/writes go through the injected store (SQLCipher in production,
/// in-memory in tests) — the registry never touches the network.
///
/// SECURITY CHECKPOINT (Task 6.5): only blind hashes + opaque public keys
/// are persisted; the store's sensitive columns are encrypted at rest.
class LocalDeviceRegistry implements DeviceRegistry {
  final EntityStore<LinkedDevice> _store;

  LocalDeviceRegistry({required EntityStore<LinkedDevice> store})
      : _store = store;

  @override
  Future<List<LinkedDevice>> list(String ownerBlindHash) async {
    final all = await _store.getAll();
    final owned = all.where((d) => d.ownerBlindHash == ownerBlindHash);
    final sorted = [...owned]..sort((a, b) => b.pairedAt.compareTo(a.pairedAt));
    return sorted;
  }

  @override
  Future<LinkedDevice?> getById(String deviceId) => _store.getById(deviceId);

  @override
  Future<void> add(LinkedDevice device) => _store.insert(device);

  @override
  Future<void> revoke(String deviceId) async {
    final device = await _store.getById(deviceId);
    if (device == null || device.revoked) {
      // Idempotent: unknown or already-revoked devices are a no-op.
      return;
    }
    await _store.update(device.copyWith(revoked: true));
  }
}
