import 'dart:typed_data';

import 'package:civic_commons/pairing/data/local_device_registry.dart';
import 'package:civic_commons/pairing/domain/linked_device.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

String _blindHash(String seed) => seed.padRight(64, 'a').substring(0, 64);

LinkedDevice _device(String id, {String owner = 'a', bool revoked = false}) {
  return LinkedDevice(
    deviceId: id,
    ownerBlindHash: _blindHash(owner),
    publicKey: Uint8List.fromList(List.filled(32, 1)),
    pairedAt: DateTime(2026, 8, 10),
    revoked: revoked,
  );
}

void main() {
  group('LocalDeviceRegistry - list', () {
    test('lists devices for an owner, newest first', () async {
      final registry = LocalDeviceRegistry(
        store: InMemoryEntityStore<LinkedDevice>((d) => d.deviceId),
      );
      await registry.add(LinkedDevice(
        deviceId: 'older',
        ownerBlindHash: _blindHash('a'),
        publicKey: Uint8List.fromList(List.filled(32, 1)),
        pairedAt: DateTime(2026, 1, 1),
      ));
      await registry.add(LinkedDevice(
        deviceId: 'newer',
        ownerBlindHash: _blindHash('a'),
        publicKey: Uint8List.fromList(List.filled(32, 1)),
        pairedAt: DateTime(2026, 8, 1),
      ));

      final devices = await registry.list(_blindHash('a'));

      expect(devices.map((d) => d.deviceId).toList(), ['newer', 'older']);
    });

    test('only returns devices owned by the given blind hash', () async {
      final registry = LocalDeviceRegistry(
        store: InMemoryEntityStore<LinkedDevice>((d) => d.deviceId),
      );
      await registry.add(_device('a1', owner: 'a'));
      await registry.add(_device('b1', owner: 'b'));

      final devices = await registry.list(_blindHash('a'));

      expect(devices.map((d) => d.deviceId).toList(), ['a1']);
    });
  });

  group('LocalDeviceRegistry - revocation (VERIFY: unit tests)', () {
    test('revoke marks the device revoked', () async {
      final registry = LocalDeviceRegistry(
        store: InMemoryEntityStore<LinkedDevice>((d) => d.deviceId),
      );
      await registry.add(_device('d1'));

      await registry.revoke('d1');

      final device = await registry.getById('d1');
      expect(device!.revoked, isTrue);
    });

    test('revoking an unknown device is a no-op', () async {
      final registry = LocalDeviceRegistry(
        store: InMemoryEntityStore<LinkedDevice>((d) => d.deviceId),
      );
      await registry.add(_device('d1'));

      await registry.revoke('does-not-exist');

      final devices = await registry.list(_blindHash('a'));
      expect(devices, hasLength(1));
      expect(devices.first.revoked, isFalse);
    });

    test('revoking an already-revoked device is a no-op (idempotent)',
        () async {
      final registry = LocalDeviceRegistry(
        store: InMemoryEntityStore<LinkedDevice>((d) => d.deviceId),
      );
      await registry.add(_device('d1', revoked: true));

      await registry.revoke('d1');

      final device = await registry.getById('d1');
      expect(device!.revoked, isTrue);
    });

    test('revoked devices remain listed (auditable history)', () async {
      final registry = LocalDeviceRegistry(
        store: InMemoryEntityStore<LinkedDevice>((d) => d.deviceId),
      );
      await registry.add(_device('d1'));
      await registry.add(_device('d2'));

      await registry.revoke('d1');

      final devices = await registry.list(_blindHash('a'));
      expect(devices, hasLength(2));
      expect(devices.firstWhere((d) => d.deviceId == 'd1').revoked, isTrue);
      expect(devices.firstWhere((d) => d.deviceId == 'd2').revoked, isFalse);
    });

    test('revoking a device in another owners list is still by device id',
        () async {
      final registry = LocalDeviceRegistry(
        store: InMemoryEntityStore<LinkedDevice>((d) => d.deviceId),
      );
      await registry.add(_device('shared', owner: 'a'));
      await registry.add(_device('shared2', owner: 'b'));

      await registry.revoke('shared');

      final ownerB = await registry.list(_blindHash('b'));
      // Only owner A's row was revoked; owner B's row is untouched.
      expect(ownerB.first.revoked, isFalse);
    });
  });
}
