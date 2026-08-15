import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/crypto/secure_key_storage.dart';
import 'package:civic_commons/pairing/domain/device_pairing_service.dart';
import 'package:civic_commons/pairing/domain/pairing_payload.dart';
import 'package:civic_commons/pairing/domain/pairing_secret.dart';
import 'package:civic_commons/signal/models.dart';
import 'package:civic_commons/signal/prekey_manager.dart';
import 'package:civic_commons/signal/session_manager.dart';
import 'package:civic_commons/signal/session_store.dart';
import 'package:civic_commons/signal/x3dh_service.dart';
import 'package:civic_commons/state/data/local_device_pairing_bloc.dart';
import 'package:civic_commons/state/domain/device_pairing_state.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

String _blindHash(String seed) => seed.padRight(64, 'a').substring(0, 64);
String _uuidV4() => 'f47ac10b-58cc-4372-a567-0e02b2c3d479';

void main() {
  late DevicePairingService service;
  late FakeQrScanner scanner;
  late InMemoryDeviceRegistry registry;

  setUp(() async {
    final crypto = CryptoServiceImpl();
    scanner = FakeQrScanner();
    registry = InMemoryDeviceRegistry();
    service = DevicePairingService(
      secrets: PairingSecretGenerator(),
      qrEncoder: FakeQrEncoder(),
      qrScanner: scanner,
      registry: registry,
      sessions: SessionManager(
        x3dh: X3DHService(cryptoService: crypto),
        crypto: crypto,
        store: InMemorySessionStore(),
      ),
      identityKeys:
          FakeIdentityKeySource(await crypto.generateEd25519KeyPair()),
    );
  });

  LocalDevicePairingBloc buildBloc({PrekeyManager? prekeyManager}) =>
      LocalDevicePairingBloc(
        service: service,
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        prekeyManager: prekeyManager,
      );

  group('LocalDevicePairingBloc - PRIMARY side', () {
    test('start emits idle', () async {
      final bloc = buildBloc();
      final states = <DevicePairingState>[];
      bloc.state.listen(states.add);

      await bloc.start();

      expect(states.last.phase, DevicePairingPhase.idle);
      await bloc.close();
    });

    test('without a prekey manager the flow stays idle (no broken QR)',
        () async {
      final bloc = buildBloc();
      final states = <DevicePairingState>[];
      bloc.state.listen(states.add);

      await bloc.start();
      await bloc.generatePairingCode();

      expect(states.last.phase, DevicePairingPhase.idle);
      expect(states.last.qrMatrix, isNull);
      await bloc.close();
    });

    test('generatePairingCode emits a qrReady state with a matrix', () async {
      final crypto = CryptoServiceImpl();
      final prekeyManager = PrekeyManager(
        cryptoService: crypto,
        secureStorage: FakeSecureKeyStorage(),
      );
      // Seed the prekey material so the bundle can be built.
      await prekeyManager.generateSignedPreKey();
      final bloc = buildBloc(prekeyManager: prekeyManager);
      final states = <DevicePairingState>[];
      bloc.state.listen(states.add);

      await bloc.start();
      await bloc.generatePairingCode();

      final last = states.last;
      expect(last.phase, DevicePairingPhase.qrReady);
      expect(last.qrMatrix, isNotNull);
      expect(last.qrPayloadText, isNotNull);
      // The payload decodes strictly (round-trip through the codec).
      expect(PairingPayload.decode(last.qrPayloadText!), isNotNull);
      await bloc.close();
    });
  });

  group('LocalDevicePairingBloc - NEW DEVICE side', () {
    test('authorizeCode emits paired on a valid code', () async {
      // Build a valid payload from the primary side, then authorize it.
      final crypto = CryptoServiceImpl();
      final primaryService = DevicePairingService(
        secrets: PairingSecretGenerator(),
        qrEncoder: FakeQrEncoder(),
        qrScanner: scanner,
        registry: registry,
        sessions: SessionManager(
          x3dh: X3DHService(cryptoService: crypto),
          crypto: crypto,
          store: InMemorySessionStore(),
        ),
        identityKeys: FakeIdentityKeySource(
          await crypto.generateEd25519KeyPair(),
        ),
      );
      final payload = await primaryService.createPairingPayload(
        ownerBlindHash: _blindHash('a'),
        deviceId: _uuidV4(),
        bundle: PreKeyBundle(
          registrationId: _uuidV4(),
          identityKey: Uint8List.fromList(List.filled(32, 7)),
          signedPreKeyId: 1,
          signedPreKey: Uint8List.fromList(List.filled(32, 7)),
          signedPreKeySignature: Uint8List.fromList(List.filled(64, 9)),
          oneTimePreKeyId: 2,
          oneTimePreKey: Uint8List.fromList(List.filled(32, 7)),
        ),
      );
      final bloc = buildBloc();
      final states = <DevicePairingState>[];
      bloc.state.listen(states.add);

      await bloc.start();
      await bloc.authorizeCode(payload.encode());

      expect(states.last.phase, DevicePairingPhase.paired);
      await bloc.close();
    });

    test('authorizeCode emits scanFailed on a PII-shaped code', () async {
      final bloc = buildBloc();
      final states = <DevicePairingState>[];
      bloc.state.listen(states.add);

      await bloc.start();
      await bloc.authorizeCode('+919876543210');

      expect(states.last.phase, DevicePairingPhase.scanFailed);
      await bloc.close();
    });

    test('reset clears back to idle', () async {
      final bloc = buildBloc();
      final states = <DevicePairingState>[];
      bloc.state.listen(states.add);

      await bloc.start();
      await bloc.reset();

      expect(states.last.phase, DevicePairingPhase.idle);
      await bloc.close();
    });
  });
}

/// Minimal [SecureKeyStorage] stub — the prekey manager only needs
/// storeSignedPreKey / getSignedPreKey / getOneTimePreKey / consume.
/// `extends` (not `implements`) so only the used members are overridden.
class FakeSecureKeyStorage extends SecureKeyStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> storeSignedPreKey(SimpleKeyPair keyPair, int keyId) async {
    _store['spk_$keyId'] = await _encodeKeyPair(keyPair);
  }

  @override
  Future<SimpleKeyPair?> getSignedPreKey(int keyId) async {
    final value = _store['spk_$keyId'];
    return value == null ? null : _decodeKeyPair(value);
  }

  @override
  Future<SimpleKeyPair?> consumeOneTimePreKey(int keyId) async {
    final value = _store.remove('otpk_$keyId');
    return value == null ? null : _decodeKeyPair(value);
  }

  @override
  Future<void> storeOneTimePreKey(SimpleKeyPair keyPair, int keyId) async {
    _store['otpk_$keyId'] = await _encodeKeyPair(keyPair);
  }

  Future<String> _encodeKeyPair(SimpleKeyPair pair) async {
    final priv = (await pair.extractPrivateKeyBytes()).join(',');
    final pub = (await pair.extractPublicKey()).bytes.join(',');
    return '$priv|$pub';
  }

  SimpleKeyPair _decodeKeyPair(String value) {
    final parts = value.split('|');
    final priv =
        Uint8List.fromList(parts[0].split(',').map(int.parse).toList());
    final pub = Uint8List.fromList(parts[1].split(',').map(int.parse).toList());
    return SimpleKeyPairData(
      priv,
      publicKey: SimplePublicKey(pub, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }
}
