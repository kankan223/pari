import 'dart:async';

import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/domain/device_handle.dart';
import 'package:civic_commons/state/domain/device_pairing_bloc.dart';
import 'package:civic_commons/state/domain/device_pairing_state.dart';
import 'package:civic_commons/state/domain/linked_devices_bloc.dart';
import 'package:civic_commons/state/domain/linked_devices_state.dart';
import 'package:civic_commons/state/ui/device_management_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFlag implements SecureFlagService {
  int enableCalls = 0;

  @override
  Future<void> disableSecureFlag() async {}

  @override
  Future<void> enableSecureFlag() async {
    enableCalls++;
  }

  @override
  Future<bool> isSecureFlagSupported() async => true;
}

class _FakeLinkedDevicesBloc implements LinkedDevicesBloc {
  final _controller =
      StreamController<LinkedDevicesState>.broadcast(sync: true);
  final List<String> revoked = [];
  LinkedDevicesState current = const LinkedDevicesState(hasLoaded: true);

  @override
  Stream<LinkedDevicesState> get state => _controller.stream;

  @override
  Future<void> start() async {
    // Mimic the real bloc: the first emission lands after an await, so the
    // widget's initState subscription (attached after refresh() is called)
    // receives it — mirroring the real DB-backed read. Microtask (not a
    // timer) so a plain tester.pump() flushes it in widget tests.
    await Future<void>.microtask(() {});
    _controller.add(current);
  }

  @override
  Future<void> refresh() async {
    await Future<void>.microtask(() {});
    _controller.add(current);
  }

  @override
  Future<void> revoke(String deviceId) async {
    revoked.add(deviceId);
    await Future<void>.microtask(() {});
    _controller.add(current);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

class _FakePairingBloc implements DevicePairingBloc {
  final _controller =
      StreamController<DevicePairingState>.broadcast(sync: true);
  final List<String> authorized = [];
  int generateCalls = 0;
  int resetCalls = 0;
  DevicePairingState current = const DevicePairingState();

  @override
  Stream<DevicePairingState> get state => _controller.stream;

  @override
  Future<void> start() async {
    _controller.add(current);
  }

  @override
  Future<void> generatePairingCode() async {
    generateCalls++;
    _controller.add(
      const DevicePairingState(
        phase: DevicePairingPhase.qrReady,
        qrPayloadText: 'civic-commons://pair?v=1',
      ),
    );
  }

  @override
  Future<void> authorizeCode(String payloadText) async {
    authorized.add(payloadText);
  }

  @override
  Future<void> reset() async {
    resetCalls++;
    _controller.add(const DevicePairingState());
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

void main() {
  testWidgets('renders linked devices via derived handles', (tester) async {
    final bloc = _FakeLinkedDevicesBloc()
      ..current = LinkedDevicesState(
        hasLoaded: true,
        devices: [
          LinkedDeviceSummary(
            deviceId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
            pairedAt: DateTime(2026, 8, 10),
          ),
        ],
      );
    final pairing = _FakePairingBloc();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DeviceManagementSheet(
          linkedDevicesBloc: bloc,
          pairingBloc: pairing,
          secureFlagService: _FakeFlag(),
        ),
      ),
    ));
    await tester.pump();

    expect(
      find.text(formatDeviceHandle('f47ac10b-58cc-4372-a567-0e02b2c3d479')),
      findsOneWidget,
    );
    // The raw UUID is never rendered.
    expect(find.text('f47ac10b-58cc-4372-a567-0e02b2c3d479'), findsNothing);
    await bloc.close();
    await pairing.close();
  });

  testWidgets('revoke button calls the bloc', (tester) async {
    final bloc = _FakeLinkedDevicesBloc()
      ..current = LinkedDevicesState(
        hasLoaded: true,
        devices: [
          LinkedDeviceSummary(
            deviceId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
            pairedAt: DateTime(2026, 8, 10),
          ),
        ],
      );
    final pairing = _FakePairingBloc();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DeviceManagementSheet(
          linkedDevicesBloc: bloc,
          pairingBloc: pairing,
          secureFlagService: _FakeFlag(),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Revoke'));
    await tester.pump();

    expect(bloc.revoked, ['f47ac10b-58cc-4372-a567-0e02b2c3d479']);
    await bloc.close();
    await pairing.close();
  });

  testWidgets('empty state shows the pair CTA', (tester) async {
    final bloc = _FakeLinkedDevicesBloc();
    final pairing = _FakePairingBloc();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DeviceManagementSheet(
          linkedDevicesBloc: bloc,
          pairingBloc: pairing,
          secureFlagService: _FakeFlag(),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Pair a new device'), findsOneWidget);
    await bloc.close();
    await pairing.close();
  });

  testWidgets('pair CTA generates the QR panel', (tester) async {
    final bloc = _FakeLinkedDevicesBloc();
    final pairing = _FakePairingBloc();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DeviceManagementSheet(
          linkedDevicesBloc: bloc,
          pairingBloc: pairing,
          secureFlagService: _FakeFlag(),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Pair a new device'));
    await tester.pump();

    expect(pairing.generateCalls, 1);
    expect(find.byType(CustomPaint), findsWidgets);
    await bloc.close();
    await pairing.close();
  });

  testWidgets('FLAG_SECURE is enabled on mount (runtime)', (tester) async {
    final flag = _FakeFlag();
    final bloc = _FakeLinkedDevicesBloc();
    final pairing = _FakePairingBloc();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DeviceManagementSheet(
          linkedDevicesBloc: bloc,
          pairingBloc: pairing,
          secureFlagService: flag,
        ),
      ),
    ));
    await tester.pump();

    expect(flag.enableCalls, 1,
        reason: 'mounting the device management sheet must enable FLAG_SECURE');
    await bloc.close();
    await pairing.close();
  });
}
