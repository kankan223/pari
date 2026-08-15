import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/pairing/data/local_device_registry.dart';
import 'package:civic_commons/pairing/domain/device_pairing_service.dart';
import 'package:civic_commons/pairing/domain/device_registry.dart';
import 'package:civic_commons/pairing/domain/linked_device.dart';
import 'package:civic_commons/pairing/domain/pairing_secret.dart';
import 'package:civic_commons/signal/session_manager.dart';
import 'package:civic_commons/signal/session_store.dart';
import 'package:civic_commons/signal/x3dh_service.dart';
import 'package:civic_commons/state/data/local_linked_devices_bloc.dart';
import 'package:civic_commons/state/domain/linked_devices_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';
import 'fakes.dart';

String _blindHash(String seed) => seed.padRight(64, 'a').substring(0, 64);

Future<DevicePairingService> _service(DeviceRegistry registry) async {
  final crypto = CryptoServiceImpl();
  return DevicePairingService(
    secrets: PairingSecretGenerator(),
    qrEncoder: FakeQrEncoder(),
    qrScanner: FakeQrScanner(),
    registry: registry,
    sessions: SessionManager(
      x3dh: X3DHService(cryptoService: crypto),
      crypto: crypto,
      store: InMemorySessionStore(),
    ),
    identityKeys: FakeIdentityKeySource(await crypto.generateEd25519KeyPair()),
  );
}

void main() {
  late LocalDeviceRegistry registry;
  late LocalLinkedDevicesBloc bloc;

  setUp(() async {
    registry = LocalDeviceRegistry(
      store: InMemoryEntityStore<LinkedDevice>((d) => d.deviceId),
    );
    bloc = LocalLinkedDevicesBloc(
      registry: registry,
      pairingService: await _service(registry),
      ownerBlindHash: _blindHash('a'),
    );
  });

  test('start emits an empty loaded state', () async {
    final states = <LinkedDevicesState>[];
    bloc.state.listen(states.add);

    await bloc.start();

    expect(states.last.hasLoaded, isTrue);
    expect(states.last.devices, isEmpty);
  });

  test('refresh projects registry rows into UI-safe summaries', () async {
    await registry.add(LinkedDevice(
      deviceId: 'd1',
      ownerBlindHash: _blindHash('a'),
      publicKey: Uint8List.fromList(List.filled(32, 1)),
      pairedAt: DateTime(2026, 8, 10),
    ));
    final states = <LinkedDevicesState>[];
    bloc.state.listen(states.add);

    await bloc.refresh();

    expect(states.last.devices, hasLength(1));
    expect(states.last.devices.first.deviceId, 'd1');
    expect(states.last.devices.first.revoked, isFalse);
  });

  test('revoke unlinks a device and refreshes the list', () async {
    await registry.add(LinkedDevice(
      deviceId: 'd1',
      ownerBlindHash: _blindHash('a'),
      publicKey: Uint8List.fromList(List.filled(32, 1)),
      pairedAt: DateTime(2026, 8, 10),
    ));
    final states = <LinkedDevicesState>[];
    bloc.state.listen(states.add);

    await bloc.start();
    await bloc.revoke('d1');

    final last = states.last;
    expect(last.devices.first.revoked, isTrue);
  });

  test('close releases the stream', () async {
    await bloc.close();
    // No error — the controller closed cleanly.
  });
}
