import 'dart:typed_data';

/// A device linked to this account via QR pairing (Task 6.5).
///
/// Mirrors the `devices` table in `AppSchema`:
/// - [ownerBlindHash] is the OWNER of this local database (a 64-hex blind
///   hash — never a phone number, never a username).
/// - [publicKey] is the linked device's opaque PUBLIC key material
///   (base64url of X3DH/identity public keys). PRIVATE keys are never stored
///   here and never travel through the QR payload.
/// - [revoked] marks a device that the user unlinked; revoked rows are kept
///   (auditable history) but excluded from the active list.
///
/// SECURITY CONTRACT (Task 6.5): this entity carries ONLY a blind hash + an
/// opaque public key. No private key material, no phones, no usernames.
class LinkedDevice {
  /// The linked device's UUID v4.
  final String deviceId;

  /// Owner of this local database (64-hex blind hash).
  final String ownerBlindHash;

  /// The linked device's opaque public key bytes.
  final Uint8List publicKey;

  final DateTime pairedAt;

  /// True once the user revokes (unlinks) this device.
  final bool revoked;

  const LinkedDevice({
    required this.deviceId,
    required this.ownerBlindHash,
    required this.publicKey,
    required this.pairedAt,
    this.revoked = false,
  });

  LinkedDevice copyWith({bool? revoked}) => LinkedDevice(
        deviceId: deviceId,
        ownerBlindHash: ownerBlindHash,
        publicKey: publicKey,
        pairedAt: pairedAt,
        revoked: revoked ?? this.revoked,
      );
}
