import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../crypto/crypto_service.dart';
import '../domain/evidence_envelope.dart';
import '../domain/evidence_ports.dart';

/// Production [EvidenceCipher] (data layer, Task 8.2).
///
/// Two-layer zero-knowledge pipeline:
/// 1. **File seal** — AES-256-GCM under a fresh per-item 32-byte DEK
///    (reuses the [CryptoService] AES-256-GCM implementation; each sealed
///    blob embeds its own random nonce).
/// 2. **DEK wrap** — the X25519 ECDH shared secret between THIS device and
///    the recipient is used as the AES-256-GCM key to wrap the DEK, so the
///    envelope travels beside the sealed file without ever exposing the DEK.
///
/// SECURITY CHECKPOINT (Task 8.2): only the WRAPPED DEK is ever persisted
/// or queued. A server holding queue bytes gets sealed files + wrapped DEKs
/// it cannot open — evidence never decrypts server-side.
class AesGcmEvidenceCipher implements EvidenceCipher {
  final CryptoService _crypto;
  final X25519 _x25519;

  /// THIS device's X25519 keypair — the wrap initiator. The recipient is
  /// dynamic (Task 8.2: the victim's own key for self-recovery; analyst
  /// keys slot in during Task 8.5).
  final SimpleKeyPair _deviceKeyPair;

  AesGcmEvidenceCipher({
    required CryptoService crypto,
    required SimpleKeyPair deviceKeyPair,
    X25519? x25519,
  })  : _crypto = crypto,
        _deviceKeyPair = deviceKeyPair,
        _x25519 = x25519 ?? X25519();

  @override
  Future<Uint8List> generateDek() async =>
      Uint8List.fromList(SecretKeyData.random(length: 32).bytes);

  @override
  Future<Uint8List> sealFile(Uint8List plaintext, Uint8List dek) {
    if (dek.length != 32) {
      throw ArgumentError('DEK must be 32 bytes for AES-256');
    }
    return _crypto.encrypt(plaintext, dek);
  }

  @override
  Future<Uint8List> openFile(Uint8List sealed, Uint8List dek) =>
      _crypto.decrypt(sealed, dek);

  @override
  Future<DekEnvelope> wrapDek(
    Uint8List dek, {
    required SimplePublicKey recipient,
  }) async {
    if (dek.length != 32) {
      throw ArgumentError('DEK must be 32 bytes for AES-256');
    }
    final shared = await _x25519.sharedSecretKey(
      keyPair: _deviceKeyPair,
      remotePublicKey: recipient,
    );
    final wrapKey = Uint8List.fromList(await shared.extractBytes());
    final sealedDek = await _crypto.encrypt(dek, wrapKey);
    // The fingerprint identifies WHICH key can unwrap — the first 8 bytes
    // of the recipient public key, hex-encoded. Not identity.
    return DekEnvelope(
      algorithm: DekEnvelope.alg,
      wrappedDek: sealedDek,
      recipientFingerprint: _keyId(recipient.bytes),
    );
  }

  @override
  Future<Uint8List> unwrapDek(
    DekEnvelope envelope, {
    required SimpleKeyPair keyPair,
  }) async {
    if (envelope.algorithm != DekEnvelope.alg) {
      throw ArgumentError(
          'unsupported DEK wrap algorithm: ${envelope.algorithm}');
    }
    // [keyPair] is the RECIPIENT's keypair (the device's own for
    // self-recovery). Verify it is the intended recipient before unwrapping.
    final recipientPublic = await keyPair.extractPublicKey();
    final fingerprint = _keyId(recipientPublic.bytes);
    if (fingerprint != envelope.recipientFingerprint) {
      throw ArgumentError(
          'DEK envelope is not wrapped for this key (fingerprint mismatch)');
    }
    // X25519 ECDH is symmetric: (device, recipient) == (recipient, device).
    final devicePublic = await _deviceKeyPair.extractPublicKey();
    final shared = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: devicePublic,
    );
    final wrapKey = Uint8List.fromList(await shared.extractBytes());
    return _crypto.decrypt(envelope.wrappedDek, wrapKey);
  }

  static String _keyId(List<int> publicKeyBytes) {
    final hex = StringBuffer();
    final n = publicKeyBytes.length < 8 ? publicKeyBytes.length : 8;
    for (var i = 0; i < n; i++) {
      hex.write(publicKeyBytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return hex.toString();
  }
}
