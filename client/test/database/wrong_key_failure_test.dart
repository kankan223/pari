import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/database/data/argon2id_database_key_service.dart';
import 'package:civic_commons/database/data/key_verification_marker.dart';

void main() {
  final crypto = CryptoServiceImpl();
  final keyService = Argon2idDatabaseKeyService(crypto);
  final marker = KeyVerificationMarker(crypto);

  group('KeyVerificationMarker - wrong key failure', () {
    test('correct key verifies the marker (decrypts successfully)', () async {
      final key = await keyService.deriveKey('123456');
      final fresh = marker.generateMarker();

      final sealed = await marker.seal(fresh, key.rawBytes);

      expect(await marker.verify(sealed, key.rawBytes), isTrue);
    });

    test('wrong key fails to verify the marker (AES-GCM auth failure)',
        () async {
      final correctKey = await keyService.deriveKey('123456');
      final wrongKey = await keyService.deriveKey('654321');
      final fresh = marker.generateMarker();

      final sealed = await marker.seal(fresh, correctKey.rawBytes);

      // The wrong key cannot decrypt: GCM authentication fails.
      expect(await marker.verify(sealed, wrongKey.rawBytes), isFalse);
    });

    test('wrong key fails even for a key one character off the correct PIN',
        () async {
      final correctKey = await keyService.deriveKey('123456');
      final nearMissKey = await keyService.deriveKey('123457');
      final fresh = marker.generateMarker();

      final sealed = await marker.seal(fresh, correctKey.rawBytes);

      expect(await marker.verify(sealed, nearMissKey.rawBytes), isFalse);
    });

    test('tampered marker fails verification', () async {
      final key = await keyService.deriveKey('123456');
      final fresh = marker.generateMarker();
      final sealed = await marker.seal(fresh, key.rawBytes);

      // Flip one byte of the sealed marker → GCM auth must fail.
      final tampered = [...sealed];
      tampered[0] = tampered[0] ^ 0xff;

      expect(
        await marker.verify(Uint8List.fromList(tampered), key.rawBytes),
        isFalse,
      );
    });

    test('sealed marker is opaque (contains no plaintext marker value)',
        () async {
      final key = await keyService.deriveKey('123456');
      // Marker value that would be recognizable if leaked in plaintext.
      final fresh = marker.generateMarker();
      final sealed = await marker.seal(fresh, key.rawBytes);
      final hex = marker.encode(sealed);

      // The stored form is 12 (GCM nonce) + 16 (ciphertext) + 16 (mac) = 44
      // bytes of ciphertext → 88 hex chars. No way to recover the marker
      // value from it without the key.
      expect(hex.length, 88);
      expect(hex, isNot(contains(marker.encode(fresh))));
    });
  });

  group('KeyVerificationMarker - storage round-trip', () {
    test('hex encode/decode round-trips the sealed marker', () async {
      final key = await keyService.deriveKey('112233');
      final sealed = await marker.seal(marker.generateMarker(), key.rawBytes);

      final decoded = marker.decode(marker.encode(sealed));

      expect(decoded, equals(sealed));
      expect(await marker.verify(decoded, key.rawBytes), isTrue);
    });
  });
}
