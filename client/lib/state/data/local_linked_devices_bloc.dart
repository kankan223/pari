import 'dart:async';

import '../../pairing/domain/device_pairing_service.dart';
import '../../pairing/domain/device_registry.dart';
import '../domain/linked_devices_bloc.dart';
import '../domain/linked_devices_state.dart';

/// Registry-backed [LinkedDevicesBloc] (data layer, Task 6.5).
///
/// Pulls the linked-device snapshot from the injected [DeviceRegistry] and
/// projects it into UI-safe [LinkedDeviceSummary]s. Revocation goes through
/// the [DevicePairingService] so the session cleanup happens too.
class LocalLinkedDevicesBloc implements LinkedDevicesBloc {
  final DeviceRegistry _registry;
  final DevicePairingService _pairingService;
  final String _ownerBlindHash;
  // sync:true — emissions are delivered synchronously to listeners, so
  // refresh()/revoke() callers (and tests) observe the new state immediately
  // after the await completes.
  final StreamController<LinkedDevicesState> _controller =
      StreamController<LinkedDevicesState>.broadcast(sync: true);

  LocalLinkedDevicesBloc({
    required DeviceRegistry registry,
    required DevicePairingService pairingService,
    required String ownerBlindHash,
  })  : _registry = registry,
        _pairingService = pairingService,
        _ownerBlindHash = ownerBlindHash;

  @override
  Stream<LinkedDevicesState> get state => _controller.stream;

  @override
  Future<void> start() async {
    await refresh();
  }

  @override
  Future<void> refresh() async {
    final devices = await _registry.list(_ownerBlindHash);
    _controller.add(
      LinkedDevicesState(
        devices:
            devices.map(LinkedDeviceSummary.fromDevice).toList(growable: false),
        hasLoaded: true,
      ),
    );
  }

  @override
  Future<void> revoke(String deviceId) async {
    await _pairingService.revokeDevice(
      deviceId: deviceId,
      ownerBlindHash: _ownerBlindHash,
    );
    await refresh();
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}
