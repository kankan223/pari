import 'dart:typed_data';

import 'package:convert/convert.dart' show hex;

import '../../crypto/crypto_service.dart';
import '../domain/app_database.dart';

/// Detects whether a key can unlock the database by verifying a stored
/// encrypted marker (data layer).
///
/// On first open (correct key), the database stores a random challenge value
/// encrypted with AES-256-GCM under the derived key. On every subsequent
/// open, the entered key is used to decrypt the marker: a correct key
/// authenticates and decrypts it, a wrong key fails AES-GCM authentication.
///
/// This mirrors exactly how SQLCipher behaves (page-level HMAC auth), and it
/// lets the wrong-key path be unit-tested with real cryptography without a
/// native SQLCipher library.
class KeyVerificationMarker {
  final CryptoService _crypto;

  const KeyVerificationMarker(this._crypto);

  /// Creates a fresh random marker value.
  Uint8List generateMarker() => _crypto.generateSalt(); // 16 random bytes

  /// Encrypts [marker] under [key] (AES-256-GCM). Safe to persist — the
  /// stored form reveals nothing about the key or the marker.
  Future<Uint8List> seal(Uint8List marker, Uint8List key) =>
      _crypto.encrypt(marker, key);

  /// Attempts to decrypt [sealed] with [key].
  ///
  /// Returns true only when [key] is the correct key (GCM auth succeeds).
  /// A wrong key throws inside the crypto layer and returns false here —
  /// never throwing [WrongDatabaseKeyException] directly, so callers can
  /// choose how to surface the failure.
  Future<bool> verify(Uint8List sealed, Uint8List key) async {
    try {
      final plaintext = await _crypto.decrypt(sealed, key);
      return plaintext.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Convenience: hex-encodes a sealed marker for storage in a TEXT column.
  String encode(Uint8List sealed) => hex.encode(sealed);

  /// Convenience: decodes a stored hex marker back to bytes.
  Uint8List decode(String sealedHex) =>
      Uint8List.fromList(hex.decode(sealedHex));
}
