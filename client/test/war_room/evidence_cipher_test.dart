import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/war_room/data/aes_gcm_evidence_cipher.dart';
import 'package:civic_commons/war_room/domain/evidence_envelope.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final plaintext = Uint8List.fromList(
      List.generate(2048, (i) => (i * 31) & 0xff)); // photo-like bytes

  Future<(AesGcmEvidenceCipher, SimpleKeyPair)> makeCipher() async {
    final device = await X25519().newKeyPair();
    final cipher = AesGcmEvidenceCipher(
      crypto: CryptoServiceImpl(),
      deviceKeyPair: device,
    );
    return (cipher, device);
  }

  group('AesGcmEvidenceCipher (Task 8.2)', () {
    test('generateDek returns fresh 32-byte keys', () async {
      final (cipher, _) = await makeCipher();
      final dek1 = await cipher.generateDek();
      final dek2 = await cipher.generateDek();
      expect(dek1, hasLength(32));
      expect(dek2, hasLength(32));
      expect(dek1, isNot(equals(dek2)), reason: 'DEKs must be unique');
    });

    test('sealFile/openFile round-trips the original bytes', () async {
      final (cipher, _) = await makeCipher();
      final dek = await cipher.generateDek();
      final sealed = await cipher.sealFile(plaintext, dek);
      final opened = await cipher.openFile(sealed, dek);
      expect(opened, equals(plaintext));
    });

    test('BYTE-LEVEL PROOF: sealed file bytes never match the plaintext',
        () async {
      final (cipher, _) = await makeCipher();
      final dek = await cipher.generateDek();
      final sealed = await cipher.sealFile(plaintext, dek);
      expect(sealed, isNot(equals(plaintext)));
      // The plaintext head must not survive into the sealed blob.
      final plaintextHead = plaintext.sublist(0, 64);
      expect(_containsBytes(sealed, plaintextHead), isFalse,
          reason: 'no plaintext fragment may survive into the sealed file');
      // Sealed output is larger than input (nonce + MAC).
      expect(sealed.length, greaterThan(plaintext.length));
    });

    test('tampered sealed file fails authentication', () async {
      final (cipher, _) = await makeCipher();
      final dek = await cipher.generateDek();
      final sealed = await cipher.sealFile(plaintext, dek);
      final tampered = Uint8List.fromList(sealed);
      tampered[sealed.length ~/ 2] ^= 0x01;
      expect(() => cipher.openFile(tampered, dek), throwsA(anything));
    });

    test('opening with the wrong DEK fails', () async {
      final (cipher, _) = await makeCipher();
      final dek = await cipher.generateDek();
      final wrong = await cipher.generateDek();
      final sealed = await cipher.sealFile(plaintext, dek);
      expect(() => cipher.openFile(sealed, wrong), throwsA(anything));
    });

    test('wrapDek/unwrapDek round-trips the DEK (self-recovery)', () async {
      final (cipher, device) = await makeCipher();
      final dek = await cipher.generateDek();
      final devicePublic = await device.extractPublicKey();

      final envelope = await cipher.wrapDek(dek, recipient: devicePublic);
      expect(envelope.algorithm, DekEnvelope.alg);
      expect(envelope.wrappedDek, isNot(equals(dek)),
          reason: 'BYTE-LEVEL PROOF: the wrapped DEK is never the plaintext');

      final unwrapped = await cipher.unwrapDek(envelope, keyPair: device);
      expect(unwrapped, equals(dek));
    });

    test('unwrap with the WRONG keypair fails (fingerprint mismatch)',
        () async {
      final (cipher, device) = await makeCipher();
      final other = await X25519().newKeyPair();
      final dek = await cipher.generateDek();
      final devicePublic = await device.extractPublicKey();
      final envelope = await cipher.wrapDek(dek, recipient: devicePublic);

      expect(
        () => cipher.unwrapDek(envelope, keyPair: other),
        throwsArgumentError,
      );
    });

    test('DekEnvelope binary codec round-trips and rejects truncation',
        () async {
      final (cipher, device) = await makeCipher();
      final dek = await cipher.generateDek();
      final devicePublic = await device.extractPublicKey();
      final envelope = await cipher.wrapDek(dek, recipient: devicePublic);

      final bytes = envelope.toBytes();
      final decoded = DekEnvelope.fromBytes(bytes);
      expect(decoded.algorithm, envelope.algorithm);
      expect(decoded.wrappedDek, envelope.wrappedDek);
      expect(decoded.recipientFingerprint, envelope.recipientFingerprint);

      // Truncated bytes must be rejected.
      expect(
        () => DekEnvelope.fromBytes(bytes.sublist(0, bytes.length - 2)),
        throwsFormatException,
      );
      expect(() => DekEnvelope.fromBytes(Uint8List(0)), throwsFormatException);
    });

    test('recovery pipeline: unwrap DEK then open the file (full path)',
        () async {
      final (cipher, device) = await makeCipher();
      final dek = await cipher.generateDek();
      final sealed = await cipher.sealFile(plaintext, dek);
      final devicePublic = await device.extractPublicKey();
      final envelope = await cipher.wrapDek(dek, recipient: devicePublic);

      // Simulate a cold restart: only the sealed file + wrapped DEK exist.
      final unwrapped = await cipher.unwrapDek(envelope, keyPair: device);
      final restored = await cipher.openFile(sealed, unwrapped);
      expect(restored, equals(plaintext));
    });
  });
}

bool _containsBytes(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) {
    return false;
  }
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}
