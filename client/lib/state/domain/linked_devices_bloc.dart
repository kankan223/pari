import 'linked_devices_state.dart';

/// BLoC for the linked-devices list (Task 6.5).
///
/// Exposes a stream of [LinkedDevicesState] derived from the local
/// [DeviceRegistry]. The UI binds to [state] only and never talks to the
/// registry or network directly (clean architecture, offline-first).
///
/// SECURITY CHECKPOINT (Task 6.5): the state carries only UI-safe
/// [LinkedDeviceSummary]s — device UUIDs + pairing dates. Raw blind hashes
/// and public key bytes never leave the state layer.
abstract class LinkedDevicesBloc {
  /// Stream of linked-device list states.
  Stream<LinkedDevicesState> get state;

  /// Starts listening to the registry and emits the current snapshot.
  Future<void> start();

  /// Re-reads the registry and emits a fresh snapshot.
  Future<void> refresh();

  /// Revokes (unlinks) the device with [deviceId]. Local-first: the registry
  /// is updated, then the list refreshes.
  Future<void> revoke(String deviceId);

  /// Releases resources.
  Future<void> close();
}
