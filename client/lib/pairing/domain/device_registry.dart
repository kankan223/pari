import 'linked_device.dart';

/// Registry of devices linked to this account (Task 6.5).
///
/// Data flows through the encrypted local store (EntityStore-backed in the
/// data layer, in-memory fakes in tests). The registry is keyed by the
/// OWNER's 64-hex blind hash — never by a phone number.
///
/// SECURITY CHECKPOINT (Task 6.5): rows hold only blind hashes + opaque
/// public keys; the whole backing file is SQLCipher-encrypted at rest.
abstract class DeviceRegistry {
  /// All devices linked to [ownerBlindHash], most recently paired first.
  Future<List<LinkedDevice>> list(String ownerBlindHash);

  /// The device with [deviceId], or null.
  Future<LinkedDevice?> getById(String deviceId);

  /// Persists a newly linked [device].
  Future<void> add(LinkedDevice device);

  /// Marks the device with [deviceId] as revoked (unlinked). Idempotent —
  /// revoking an unknown or already-revoked device is a no-op.
  Future<void> revoke(String deviceId);
}
