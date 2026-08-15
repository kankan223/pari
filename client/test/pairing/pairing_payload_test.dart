import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/pairing/domain/pairing_payload.dart';
import 'package:civic_commons/pairing/domain/pairing_secret.dart';
import 'package:flutter_test/flutter_test.dart';

/// 32-byte public-key-shaped UNPADDED base64url value (X25519/Ed25519 key
/// size) — matches the wire encoding (padding is stripped like the Go relay's
/// base64.RawURLEncoding).
final String _key32 = base64Url
    .encode(Uint8List.fromList(List.filled(32, 7)))
    .replaceAll('=', '');

/// 64-byte signature-shaped UNPADDED base64url value.
final String _sig64 = base64Url
    .encode(Uint8List.fromList(List.filled(64, 9)))
    .replaceAll('=', '');

String _blindHash(String seed) => seed.padRight(64, 'a').substring(0, 64);

String _uuidV4() => 'f47ac10b-58cc-4372-a567-0e02b2c3d479';

PairingPayload _validPayload({String? secret, int? expiresAt}) {
  return PairingPayload(
    ownerBlindHash: _blindHash('a'),
    deviceId: _uuidV4(),
    pairingSecret: secret ?? PairingSecretGenerator().generate(),
    expiresAtMs: expiresAt ?? 9999999999999,
    identityKey: _key32,
    signedPreKeyId: 1,
    signedPreKey: _key32,
    signedPreKeySignature: _sig64,
    oneTimePreKeyId: 2,
    oneTimePreKey: _key32,
  );
}

void main() {
  group('PairingPayload - codec round-trip', () {
    test('encode → decode preserves every field', () {
      final payload = _validPayload();

      final decoded = PairingPayload.decode(payload.encode());

      expect(decoded, isNotNull);
      expect(decoded!.version, 1);
      expect(decoded.ownerBlindHash, payload.ownerBlindHash);
      expect(decoded.deviceId, payload.deviceId);
      expect(decoded.pairingSecret, payload.pairingSecret);
      expect(decoded.expiresAtMs, payload.expiresAtMs);
      expect(decoded.identityKey, payload.identityKey);
      expect(decoded.signedPreKeyId, payload.signedPreKeyId);
      expect(decoded.signedPreKey, payload.signedPreKey);
      expect(decoded.signedPreKeySignature, payload.signedPreKeySignature);
      expect(decoded.oneTimePreKeyId, payload.oneTimePreKeyId);
      expect(decoded.oneTimePreKey, payload.oneTimePreKey);
    });

    test('decode is stable across encode/decode cycles (idempotent)', () {
      final once = PairingPayload.decode(_validPayload().encode());
      final twice = PairingPayload.decode(once!.encode());

      expect(twice!.encode(), once.encode());
    });

    test('one-time prekey is optional', () {
      final payload = PairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        pairingSecret: PairingSecretGenerator().generate(),
        expiresAtMs: 9999999999999,
        identityKey: _key32,
        signedPreKeyId: 1,
        signedPreKey: _key32,
        signedPreKeySignature: _sig64,
      );

      final decoded = PairingPayload.decode(payload.encode());

      expect(decoded, isNotNull);
      expect(decoded!.oneTimePreKeyId, isNull);
      expect(decoded.oneTimePreKey, isNull);
    });
  });

  group('PairingPayload - SECURITY CHECKPOINT (strict validation)', () {
    test('rejects a non-civic-commons URI', () {
      expect(PairingPayload.decode('https://example.com/pair?bh=x'), isNull);
      expect(PairingPayload.decode('civic-commons://other?v=1'), isNull);
      expect(PairingPayload.decode('garbage'), isNull);
      expect(PairingPayload.decode(''), isNull);
    });

    test('rejects a wrong version', () {
      final text = _validPayload()
          .encode()
          .replaceFirst('civic-commons://pair?v=1', 'civic-commons://pair?v=2');
      expect(PairingPayload.decode(text), isNull);
    });

    test('rejects a non-64-hex blind hash (phones/usernames are impossible)',
        () {
      final payload = _validPayload();
      final text = payload
          .encode()
          .replaceFirst('bh=${payload.ownerBlindHash}', 'bh=+919876543210');
      expect(PairingPayload.decode(text), isNull);
    });

    test('rejects a phone-shaped blind hash', () {
      final text = 'civic-commons://pair?v=1&bh=+919876543210&did=${_uuidV4()}'
          '&sec=abc&exp=1&ik=$_key32&spkid=1&spk=$_key32&sig=$_sig64';
      expect(PairingPayload.decode(text), isNull);
    });

    test('rejects a username-shaped blind hash', () {
      final text = 'civic-commons://pair?v=1&bh=alice&did=${_uuidV4()}'
          '&sec=abc&exp=1&ik=$_key32&spkid=1&spk=$_key32&sig=$_sig64';
      expect(PairingPayload.decode(text), isNull);
    });

    test('rejects a non-UUID device id', () {
      final text =
          _validPayload().encode().replaceFirst(_uuidV4(), 'not-a-uuid');
      expect(PairingPayload.decode(text), isNull);
    });

    test('rejects a malformed pairing secret', () {
      final text =
          _validPayload().encode().replaceFirst('sec=', 'sec=not_base64url!');
      expect(PairingPayload.decode(text), isNull);
    });

    test('rejects missing required fields', () {
      final base = _validPayload().encode();
      for (final field in [
        'bh',
        'did',
        'sec',
        'exp',
        'ik',
        'spkid',
        'spk',
        'sig',
      ]) {
        final without =
            base.split('&').where((p) => !p.startsWith('$field=')).join('&');
        expect(PairingPayload.decode(without), isNull,
            reason: 'payload missing $field must be rejected');
      }
    });

    test('rejects a one-time prekey with an id but no key', () {
      final text = _validPayload()
          .encode()
          .split('&otpk=')
          .first; // drop the otpk value but keep otpkid
      expect(PairingPayload.decode(text), isNull);
    });

    test('rejects keys that are not valid base64url bytes of wire size', () {
      final payload = _validPayload();
      final badKey = base64Url.encode(Uint8List.fromList(List.filled(16, 1)));
      final text = payload.encode().replaceFirst('ik=$_key32', 'ik=$badKey');
      expect(PairingPayload.decode(text), isNull);
    });
  });

  group('PairingPayload - expiry', () {
    test('isExpiredAt returns true after the window', () {
      final payload = _validPayload(expiresAt: 1000);
      expect(payload.isExpiredAt(999), isFalse);
      expect(payload.isExpiredAt(1000), isFalse); // inclusive bound
      expect(payload.isExpiredAt(1001), isTrue);
    });
  });

  group('PairingPayload - key material extraction', () {
    test('toKeyMaterial reconstructs the public keys only', () {
      final payload = _validPayload();

      final material = payload.toKeyMaterial();

      expect(material, isNotNull);
      expect(material!.$1, Uint8List.fromList(List.filled(32, 7)));
      expect(material.$2, 1); // signed prekey id
      expect(material.$3, Uint8List.fromList(List.filled(32, 7)));
      expect(material.$4, Uint8List.fromList(List.filled(64, 9)));
      expect(material.$5, 2); // one-time prekey id
      expect(material.$6, Uint8List.fromList(List.filled(32, 7)));
    });

    test('toKeyMaterial handles a payload without a one-time prekey', () {
      final payload = PairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        pairingSecret: PairingSecretGenerator().generate(),
        expiresAtMs: 9999999999999,
        identityKey: _key32,
        signedPreKeyId: 1,
        signedPreKey: _key32,
        signedPreKeySignature: _sig64,
      );

      final material = payload.toKeyMaterial();

      expect(material, isNotNull);
      expect(material!.$5, isNull);
      expect(material.$6, isNull);
    });
  });

  group('PairingSecretGenerator', () {
    test('generates a 43-char base64url secret (32 bytes, unpadded)', () {
      final secret = PairingSecretGenerator().generate();

      expect(secret.length, 43);
      expect(PairingPayload.isValidPairingSecret(secret), isTrue);
    });

    test('two secrets differ (entropy)', () {
      final a = PairingSecretGenerator().generate();
      final b = PairingSecretGenerator().generate();
      expect(a, isNot(b));
    });

    test('accepts only exact 32-byte base64url secrets', () {
      expect(PairingPayload.isValidPairingSecret('a' * 43), isTrue);
      expect(PairingPayload.isValidPairingSecret('a' * 42), isFalse);
      expect(PairingPayload.isValidPairingSecret('a' * 44), isFalse);
      // PII-shaped secrets (phones, e-mails) can never validate.
      expect(PairingPayload.isValidPairingSecret('+919876543210'), isFalse);
      expect(PairingPayload.isValidPairingSecret('user@example.com'), isFalse);
    });
  });
}
