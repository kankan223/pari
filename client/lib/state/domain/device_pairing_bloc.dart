import 'device_pairing_state.dart';

/// BLoC for the QR device-pairing flow (Task 6.5).
///
/// Exposes a stream of [DevicePairingState]. The UI binds to [state] only:
/// the QR matrix is rendered as pixels, never as a raw text string.
///
/// SECURITY CHECKPOINT (Task 6.5): the state carries the payload text ONLY
/// to encode it into a [QrMatrix] — widgets never print or display it. No
/// PII-shaped value can reach the state (the pairing service hard-rejects
/// anything that is not a strict 64-hex blind hash + public keys).
abstract class DevicePairingBloc {
  /// Stream of pairing-flow states.
  Stream<DevicePairingState> get state;

  /// Starts the flow (idle).
  Future<void> start();

  /// PRIMARY side: generates a fresh pairing payload + QR matrix for
  /// display. Fails the flow (idle) when the primary key bundle is missing.
  Future<void> generatePairingCode();

  /// NEW DEVICE side: authorizes a captured/entered pairing code string.
  /// On success the phase becomes [DevicePairingPhase.paired].
  Future<void> authorizeCode(String payloadText);

  /// Clears the current QR payload (e.g. after the pairing window closes).
  Future<void> reset();

  /// Releases resources.
  Future<void> close();
}
