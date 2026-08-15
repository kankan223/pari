import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/pairing/domain/device_pairing_service.dart';
import 'package:civic_commons/pairing/domain/pairing_payload.dart';
import 'package:civic_commons/pairing/domain/pairing_secret.dart';
import 'package:civic_commons/signal/models.dart';
import 'package:civic_commons/signal/session_manager.dart';
import 'package:civic_commons/signal/session_store.dart';
import 'package:civic_commons/signal/x3dh_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final Uint8List _key32 = Uint8List.fromList(List.filled(32, 7));
final Uint8List _sig64 = Uint8List.fromList(List.filled(64, 9));

String _blindHash(String seed) => seed.padRight(64, 'a').substring(0, 64);

String _uuidV4() => 'f47ac10b-58cc-4372-a567-0e02b2c3d479';

PreKeyBundle _bundle() => PreKeyBundle(
      registrationId: _uuidV4(),
      identityKey: _key32,
      signedPreKeyId: 1,
      signedPreKey: _key32,
      signedPreKeySignature: _sig64,
      oneTimePreKeyId: 2,
      oneTimePreKey: _key32,
    );

class _Harness {
  final crypto = CryptoServiceImpl();
  late final SessionManager sessions;
  final scanner = FakeQrScanner();
  final encoder = FakeQrEncoder();
  final registry = InMemoryDeviceRegistry();
  final secretGen = PairingSecretGenerator();
  late final SimpleKeyPair identity;

  Future<void> setup() async {
    sessions = SessionManager(
      x3dh: X3DHService(cryptoService: crypto),
      crypto: crypto,
      store: InMemorySessionStore(),
    );
    identity = await crypto.generateEd25519KeyPair();
  }

  DevicePairingService service() => DevicePairingService(
        secrets: secretGen,
        qrEncoder: encoder,
        qrScanner: scanner,
        registry: registry,
        sessions: sessions,
        identityKeys: FakeIdentityKeySource(identity),
      );
}

void main() {
  late _Harness h;

  setUp(() async {
    h = _Harness();
    await h.setup();
  });

  group('DevicePairingService - PRIMARY side (QR generation)', () {
    test('createPairingPayload embeds public keys + a one-time secret',
        () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );

      expect(payload.ownerBlindHash, _blindHash('a'));
      expect(payload.deviceId, _uuidV4());
      expect(
          PairingPayload.isValidPairingSecret(payload.pairingSecret), isTrue);
      expect(payload.expiresAtMs,
          greaterThan(DateTime.now().millisecondsSinceEpoch));
      expect(payload.identityKey, isNotEmpty);
      expect(payload.signedPreKey, isNotEmpty);
      expect(payload.signedPreKeySignature, isNotEmpty);
      expect(payload.oneTimePreKey, isNotNull);
    });

    test('SECURITY CHECKPOINT: payload carries ONLY public material', () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );
      final text = payload.encode();

      // No private key words can exist in the QR payload encoding.
      expect(text.toLowerCase(), isNot(contains('private')));
      expect(text.toLowerCase(), isNot(contains('secret_key')));
      expect(text.toLowerCase(), isNot(contains('privkey')));
    });

    test(
        'SECURITY CHECKPOINT: the QR signature is REAL and verifies '
        'against the embedded identity key (code-review hardening)', () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );
      final material = payload.toKeyMaterial()!;

      // The payload's embedded identity key must be the harness identity's
      // public key (the signer), and the signature must verify over the
      // signed prekey.
      final signerPub = await h.identity.extractPublicKey();
      expect(material.$1, signerPub.bytes);

      final verified = await Ed25519().verify(
        material.$3, // signedPreKey
        signature: Signature(
          material.$4,
          publicKey: SimplePublicKey(material.$1, type: KeyPairType.ed25519),
        ),
      );
      expect(verified, isTrue,
          reason: 'the payload signature must verify cryptographically');
    });

    test('encodeQr routes the payload text through the encoder', () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );

      final matrix = service.encodeQr(payload);

      expect(h.encoder.encoded, contains(payload.encode()));
      expect(matrix.moduleCount, greaterThan(0));
    });
  });

  group('DevicePairingService - NEW DEVICE side (authorize)', () {
    test('scanAndAuthorize with no code returns null', () async {
      final service = h.service();
      h.scanner.nextScan = null;

      final device = await service.scanAndAuthorize(
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );

      expect(device, isNull);
      expect(h.scanner.scanCount, 1);
    });

    test('a valid unexpired payload authorizes + registers the primary',
        () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );
      final newDeviceId = _uuidV4();

      final device = await service.authorizePayloadText(
        payload.encode(),
        ownerBlindHash: _blindHash('a'),
        newDeviceId: newDeviceId,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );

      expect(device, isNotNull);
      expect(device!.deviceId, payload.deviceId);
      expect(device.ownerBlindHash, _blindHash('a'));
      expect(device.revoked, isFalse);
      // The session with the primary was established (keyed by blind hash).
      expect(await h.sessions.hasSession(_blindHash('a')), isTrue);
    });

    test('an expired payload is rejected (no session, no registration)',
        () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );

      final device = await service.authorizePayloadText(
        payload.encode(),
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
        nowMs: payload.expiresAtMs + 1,
      );

      expect(device, isNull);
      expect(await h.sessions.hasSession(_blindHash('a')), isFalse);
      expect(await h.registry.list(_blindHash('a')), isEmpty);
    });

    test('a payload for another account is rejected outright', () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );

      final device = await service.authorizePayloadText(
        payload.encode(),
        ownerBlindHash: _blindHash('b'), // different account
        newDeviceId: _uuidV4(),
      );

      expect(device, isNull);
      expect(await h.registry.list(_blindHash('b')), isEmpty);
    });

    test('a malformed / PII-shaped payload is rejected before any side effect',
        () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );
      // Corrupt the blind hash into a phone number.
      final tampered = payload
          .encode()
          .replaceFirst('bh=${_blindHash('a')}', 'bh=+919876543210');

      final device = await service.authorizePayloadText(
        tampered,
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );

      expect(device, isNull);
      expect(await h.sessions.hasSession(_blindHash('a')), isFalse);
      expect(await h.registry.list(_blindHash('a')), isEmpty);
    });

    test(
        'SECURITY CHECKPOINT: a tampered signed prekey is rejected '
        '(signature verification, code-review hardening)', () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );
      // Flip one byte of the signed prekey inside the QR text.
      final material = payload.toKeyMaterial()!;
      final spk = Uint8List.fromList(material.$3);
      spk[0] ^= 0x01;
      final tamperedSig = base64Url.encode(spk).replaceAll('=', '');
      final tampered = payload.encode().replaceFirst(
            'spk=${payload.signedPreKey}',
            'spk=$tamperedSig',
          );

      final device = await service.authorizePayloadText(
        tampered,
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );

      expect(device, isNull,
          reason: 'a substituted signed prekey must fail signature '
              'verification — never authorize a tampered QR');
      expect(await h.sessions.hasSession(_blindHash('a')), isFalse);
      expect(await h.registry.list(_blindHash('a')), isEmpty);
    });

    test('SECURITY CHECKPOINT: a tampered identity key is rejected', () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );
      // Swap in a DIFFERENT identity public key: the signature no longer
      // verifies against it.
      final other = await h.crypto.generateEd25519KeyPair();
      final otherPub = await other.extractPublicKey();
      final otherB64 = base64Url.encode(otherPub.bytes).replaceAll('=', '');
      final tampered = payload.encode().replaceFirst(
            'ik=${payload.identityKey}',
            'ik=$otherB64',
          );

      final device = await service.authorizePayloadText(
        tampered,
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );

      expect(device, isNull,
          reason: 'a payload whose signature does not match its identity '
              'key must never authorize');
    });

    test(
        'SECURITY CHECKPOINT: the one-time secret is single-use '
        '(replay rejected, code-review hardening)', () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );
      final text = payload.encode();

      final first = await service.authorizePayloadText(
        text,
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );
      final second = await service.authorizePayloadText(
        text,
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );

      expect(first, isNotNull);
      expect(second, isNull,
          reason: 'a pairing secret already consumed cannot authorize '
              'again — replay protection');
      expect(await h.registry.list(_blindHash('a')), hasLength(1));
    });

    test('a DIFFERENT payload still authorizes after one is consumed',
        () async {
      final service = h.service();
      final payloadA = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        bundle: _bundle(),
      );
      final payloadB = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: '11111111-2222-4333-8444-555555555555',
        bundle: _bundle(),
      );

      final a = await service.authorizePayloadText(
        payloadA.encode(),
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );
      final b = await service.authorizePayloadText(
        payloadB.encode(),
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );

      expect(a, isNotNull);
      expect(b, isNotNull,
          reason: 'a fresh QR with its own secret must still pair');
      expect(await h.registry.list(_blindHash('a')), hasLength(2));
    });
  });

  group('DevicePairingService - revocation (VERIFY: unit tests)', () {
    test('revokeDevice unlinks the device and deletes the session', () async {
      final service = h.service();
      final payload = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: _bundle(),
      );
      await service.authorizePayloadText(
        payload.encode(),
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );
      expect(await h.sessions.hasSession(_blindHash('a')), isTrue);

      await service.revokeDevice(
        deviceId: payload.deviceId,
        ownerBlindHash: _blindHash('a'),
      );

      // Session gone (paired devices stop trusting the unlinked device).
      expect(await h.sessions.hasSession(_blindHash('a')), isFalse);
      // Registry row remains but marked revoked (auditable history).
      final row = await h.registry.getById(payload.deviceId);
      expect(row!.revoked, isTrue);
      // The active list no longer includes it.
      final active = await service.listDevices(_blindHash('a'));
      expect(active, isEmpty);
    });

    test('revoking an unknown device is a no-op', () async {
      final service = h.service();
      await service.revokeDevice(
        deviceId: 'does-not-exist',
        ownerBlindHash: _blindHash('a'),
      );
      expect(await service.listDevices(_blindHash('a')), isEmpty);
    });
  });

  group('DevicePairingService - device listing', () {
    test('listDevices returns only active (non-revoked) devices', () async {
      final service = h.service();
      final payloadA = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        bundle: _bundle(),
      );
      final payloadB = await service.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: '11111111-2222-4333-8444-555555555555',
        bundle: _bundle(),
      );
      await service.authorizePayloadText(
        payloadA.encode(),
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );
      await service.authorizePayloadText(
        payloadB.encode(),
        ownerBlindHash: _blindHash('a'),
        newDeviceId: _uuidV4(),
      );
      await service.revokeDevice(
        deviceId: payloadA.deviceId,
        ownerBlindHash: _blindHash('a'),
      );

      final active = await service.listDevices(_blindHash('a'));

      expect(active.map((d) => d.deviceId).toList(), [payloadB.deviceId]);
    });
  });
}
