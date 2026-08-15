import 'dart:async';
import 'dart:typed_data';

import '../../pairing/domain/device_pairing_service.dart';
import '../../signal/models.dart';
import '../../signal/prekey_manager.dart';
import '../domain/device_pairing_bloc.dart';
import '../domain/device_pairing_state.dart';

/// [DevicePairingBloc] backed by [DevicePairingService] (data layer,
/// Task 6.5).
///
/// Two roles on the same stream:
///  - PRIMARY: [generatePairingCode] builds a fresh payload + QR matrix.
///  - NEW DEVICE: [authorizeCode] validates a scanned/entered code and, on
///    success, flips the phase to [DevicePairingPhase.paired].
class LocalDevicePairingBloc implements DevicePairingBloc {
  final DevicePairingService _service;
  final String _ownerBlindHash;

  /// The current device's own UUID (used as the primary device id when
  /// generating a QR, and as the new-device id when authorizing).
  final String _deviceId;

  /// Supplies the PRIMARY's public key bundle for QR generation. Null when
  /// no prekey material exists yet (the flow stays idle — a primary must
  /// have published prekeys before it can be scanned).
  final PrekeyManager? _prekeyManager;

  // sync:true — emissions are delivered synchronously to listeners, so
  // generatePairingCode()/authorizeCode() callers (and tests) observe the
  // new phase immediately after the await completes.
  final StreamController<DevicePairingState> _controller =
      StreamController<DevicePairingState>.broadcast(sync: true);

  LocalDevicePairingBloc({
    required DevicePairingService service,
    required String ownerBlindHash,
    required String deviceId,
    PrekeyManager? prekeyManager,
  })  : _service = service,
        _ownerBlindHash = ownerBlindHash,
        _deviceId = deviceId,
        _prekeyManager = prekeyManager;

  @override
  Stream<DevicePairingState> get state => _controller.stream;

  @override
  Future<void> start() async {
    _controller.add(const DevicePairingState());
  }

  @override
  Future<void> generatePairingCode() async {
    final prekeyManager = _prekeyManager;
    if (prekeyManager == null) {
      // No prekey material — a primary cannot be scanned yet. Stay idle
      // rather than emit a broken QR.
      _controller.add(const DevicePairingState());
      return;
    }
    // Our own identity public key comes from secure storage; the bundle
    // (signed prekey etc.) comes from the prekey manager.
    final bundle = await _prekeyBundle(prekeyManager);
    if (bundle == null) {
      _controller.add(const DevicePairingState());
      return;
    }
    final payload = await _service.createPairingPayload(
      ownerBlindHash: _ownerBlindHash,
      deviceId: _deviceId,
      bundle: bundle,
    );
    _controller.add(
      DevicePairingState(
        phase: DevicePairingPhase.qrReady,
        qrPayloadText: payload.encode(),
        qrMatrix: _service.encodeQr(payload),
      ),
    );
  }

  @override
  Future<void> authorizeCode(String payloadText) async {
    _controller.add(
      const DevicePairingState(phase: DevicePairingPhase.authorizing),
    );
    final device = await _service.authorizePayloadText(
      payloadText,
      ownerBlindHash: _ownerBlindHash,
      newDeviceId: _deviceId,
    );
    _controller.add(
      DevicePairingState(
        phase: device == null
            ? DevicePairingPhase.scanFailed
            : DevicePairingPhase.paired,
      ),
    );
  }

  @override
  Future<void> reset() async {
    _controller.add(
      const DevicePairingState(phase: DevicePairingPhase.idle),
    );
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  /// Builds the primary's public [PreKeyBundle] from the prekey manager +
  /// the stored identity key, or null when the identity key is missing.
  Future<PreKeyBundle?> _prekeyBundle(PrekeyManager prekeyManager) async {
    final identityPublicKey = await _service.loadIdentityPublicKey();
    final signedPreKey = await prekeyManager.getCurrentSignedPreKey();
    final oneTimePreKey = await prekeyManager.getOneTimePreKey();
    if (signedPreKey == null) {
      return null;
    }
    return PreKeyBundle(
      registrationId: _deviceId,
      identityKey: Uint8List.fromList(identityPublicKey.bytes),
      signedPreKeyId: signedPreKey.keyId,
      signedPreKey: signedPreKey.publicKey,
      // Placeholder — DevicePairingService.createPairingPayload RE-SIGNS
      // the signed prekey with the Ed25519 identity key (never trusts this
      // value) so the QR always carries a real, verifiable signature.
      signedPreKeySignature: Uint8List(64),
      oneTimePreKeyId: oneTimePreKey?.keyId,
      oneTimePreKey: oneTimePreKey?.publicKey,
    );
  }
}
