import '../../pairing/domain/linked_device.dart';

/// UI-safe projection of a linked device (Task 6.5).
///
/// Carries only the device's UUID and pairing date — the raw owner blind
/// hash and public key bytes NEVER reach the widget tree. The UI renders the
/// device through [formatDeviceHandle] (derived non-PII handle).
class LinkedDeviceSummary {
  final String deviceId;
  final DateTime pairedAt;
  final bool revoked;

  const LinkedDeviceSummary({
    required this.deviceId,
    required this.pairedAt,
    this.revoked = false,
  });

  factory LinkedDeviceSummary.fromDevice(LinkedDevice device) =>
      LinkedDeviceSummary(
        deviceId: device.deviceId,
        pairedAt: device.pairedAt,
        revoked: device.revoked,
      );
}

/// Immutable BLoC state for the linked-devices list (Task 6.5).
class LinkedDevicesState {
  final List<LinkedDeviceSummary> devices;
  final bool hasLoaded;

  const LinkedDevicesState({
    this.devices = const [],
    this.hasLoaded = false,
  });

  LinkedDevicesState copyWith({
    List<LinkedDeviceSummary>? devices,
    bool? hasLoaded,
  }) =>
      LinkedDevicesState(
        devices: devices ?? this.devices,
        hasLoaded: hasLoaded ?? this.hasLoaded,
      );
}
