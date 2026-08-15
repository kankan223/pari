import '../../pairing/domain/qr_matrix.dart';

/// Lifecycle phase of the device-pairing flow (Task 6.5).
enum DevicePairingPhase {
  /// Not started.
  idle,

  /// The primary payload + QR are ready to display.
  qrReady,

  /// The new device captured a code and is authorizing it.
  authorizing,

  /// The new device successfully paired.
  paired,

  /// The scan produced no code / the payload failed validation.
  scanFailed,
}

/// Immutable BLoC state for the QR device-pairing flow (Task 6.5).
///
/// SECURITY CHECKPOINT: the state carries the QR payload TEXT (which is
/// displayed as the QR, not as text) and the [QrMatrix] — the widget
/// renders the matrix, never the raw text. No blind hashes or key material
/// are exposed to widgets as strings.
class DevicePairingState {
  final DevicePairingPhase phase;

  /// The encoded pairing payload text (rendered ONLY as a QR matrix).
  final String? qrPayloadText;

  /// The renderable QR matrix for the current payload.
  final QrMatrix? qrMatrix;

  const DevicePairingState({
    this.phase = DevicePairingPhase.idle,
    this.qrPayloadText,
    this.qrMatrix,
  });

  DevicePairingState copyWith({
    DevicePairingPhase? phase,
    String? qrPayloadText,
    QrMatrix? qrMatrix,
    bool clearPayload = false,
  }) =>
      DevicePairingState(
        phase: phase ?? this.phase,
        qrPayloadText:
            clearPayload ? null : (qrPayloadText ?? this.qrPayloadText),
        qrMatrix: clearPayload ? null : (qrMatrix ?? this.qrMatrix),
      );
}
