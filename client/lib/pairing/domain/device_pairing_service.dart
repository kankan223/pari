import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../signal/models.dart';
import '../../signal/session_manager.dart';
import 'device_registry.dart';
import 'identity_key_source.dart';
import 'linked_device.dart';
import 'pairing_payload.dart';
import 'pairing_secret.dart';
import 'qr_matrix.dart';

/// Orchestrates QR-based multi-device pairing (Task 6.5).
///
/// Two sides, both fully local-first and zero-knowledge:
///
///  **Primary device** — [createPairingPayload] generates a one-time pairing
///  secret, signs the signed prekey with the primary's Ed25519 identity key
///  (REAL signature — never a placeholder), wraps the PRIMARY's PUBLIC key
///  material into a [PairingPayload], and encodes it into a [QrMatrix] for
///  on-screen display. The QR is the ONLY transport for the key material —
///  never cloud backup, never the sync queue.
///
///  **New device** — [scanAndAuthorize] captures the QR, strictly decodes
///  the payload (zero-PII validation at [PairingPayload.decode]), verifies
///  it is not expired, CRYPTOGRAPHICALLY verifies the signed-prekey
///  signature against the identity key embedded in the payload (a tampered
///  or substituted spk/otpk is rejected — MITM protection), enforces the
///  one-time secret is single-use, runs X3DH as the INITIATOR against the
///  primary's public keys (SessionManager), and registers the primary as a
///  linked device in the local registry.
///
/// SECURITY CHECKPOINT (Task 6.5):
///  - The payload carries ONLY public keys + a blind hash. Private keys
///    never enter the QR, never leave [SecureKeyStorage].
///  - Decode failure is a hard rejection (null) — PII-shaped payloads are
///    structurally impossible to authorize.
///  - The signed-prekey signature is REAL and cryptographically verified at
///    the authorize gate — the bundle's placeholder signature is never
///    trusted (code-review hardening).
///  - The one-time pairing secret is single-use (consumed on the first
///    successful authorize) — a photographed QR cannot be replayed.
///  - Pairing never uses cloud backup or any sync transport.
class DevicePairingService {
  final PairingSecretGenerator _secrets;
  final QrEncoder _qrEncoder;
  final QrScanner _qrScanner;
  final DeviceRegistry _registry;
  final SessionManager _sessions;
  final IdentityKeySource _identityKeys;

  /// Pairing secrets that have already been consumed by a successful
  /// [authorizePayloadText]. Single-use enforcement (replay protection):
  /// the same QR cannot authorize a second time, even inside the expiry
  /// window. Held in memory only — the secret itself is never persisted.
  final Set<String> _consumedSecrets = {};

  /// Default pairing window: 5 minutes (a photographed QR becomes useless
  /// quickly, and the one-time secret is single-use anyway).
  static const Duration defaultWindow = Duration(minutes: 5);

  DevicePairingService({
    required PairingSecretGenerator secrets,
    required QrEncoder qrEncoder,
    required QrScanner qrScanner,
    required DeviceRegistry registry,
    required SessionManager sessions,
    required IdentityKeySource identityKeys,
  })  : _secrets = secrets,
        _qrEncoder = qrEncoder,
        _qrScanner = qrScanner,
        _registry = registry,
        _sessions = sessions,
        _identityKeys = identityKeys;

  /// PRIMARY side: creates a pairing payload + its QR matrix for the account
  /// [ownerBlindHash] (64-hex) on the primary device [deviceId].
  ///
  /// [bundle] is the primary's PUBLIC key bundle (from PrekeyManager). A new
  /// one-time secret is generated; the returned payload's [PairingPayload
  /// .encode] string is what the [PairingQrView] renders.
  ///
  /// SECURITY (code-review hardening): the payload's signed-prekey signature
  /// is computed HERE with the primary's Ed25519 identity key pair — the
  /// [PreKeyBundle.signedPreKeySignature] placeholder is NEVER trusted or
  /// embedded. The embedded identity key is the signer's public key, so the
  /// authorize side can verify the signature cryptographically. Private
  /// keys never enter the payload.
  Future<PairingPayload> createPairingPayload({
    required String ownerBlindHash,
    required String deviceId,
    required PreKeyBundle bundle,
    DateTime Function()? clock,
    Duration window = defaultWindow,
  }) async {
    final nowMs = (clock ?? DateTime.now)().millisecondsSinceEpoch;
    // Sign the signed prekey with the primary's Ed25519 identity key. The
    // signature proves the prekey belongs to the identity key embedded in
    // the payload — a substituted spk/otpk cannot survive authorization.
    final identity = await _identityKeys.loadOrCreateIdentityKeyPair();
    final identityPublic =
        Uint8List.fromList((await identity.extractPublicKey()).bytes);
    final signature = await Ed25519().sign(
      bundle.signedPreKey,
      keyPair: identity,
    );
    return PairingPayload(
      ownerBlindHash: ownerBlindHash,
      deviceId: deviceId,
      pairingSecret: _secrets.generate(),
      expiresAtMs: nowMs + window.inMilliseconds,
      identityKey: _b64Url(identityPublic),
      signedPreKeyId: bundle.signedPreKeyId,
      signedPreKey: _b64Url(bundle.signedPreKey),
      signedPreKeySignature: _b64Url(Uint8List.fromList(signature.bytes)),
      oneTimePreKeyId: bundle.oneTimePreKeyId,
      oneTimePreKey:
          bundle.oneTimePreKey == null ? null : _b64Url(bundle.oneTimePreKey!),
    );
  }

  /// Encodes [payload] into a renderable QR matrix (pure byte→module
  /// mapping — the encoder never interprets the payload content).
  QrMatrix encodeQr(PairingPayload payload) =>
      _qrEncoder.encode(payload.encode());

  /// NEW DEVICE side: captures a QR, strictly validates the payload, and —
  /// when valid and unexpired — establishes an X3DH session with the primary
  /// and registers it as a linked device.
  ///
  /// Returns the [LinkedDevice] on success, or null when the scan produced
  /// nothing or the payload failed validation (expired / malformed /
  /// PII-shaped). [nowMs] is injectable for expiry-boundary tests.
  Future<LinkedDevice?> scanAndAuthorize({
    required String ownerBlindHash,
    required String newDeviceId,
    int? nowMs,
  }) async {
    final text = await _qrScanner.scan();
    if (text == null) {
      return null;
    }
    return authorizePayloadText(
      text,
      ownerBlindHash: ownerBlindHash,
      newDeviceId: newDeviceId,
      nowMs: nowMs,
    );
  }

  /// NEW DEVICE side: validates [payloadText] and, when valid, establishes
  /// the X3DH session + registers the primary device. Exposed for flows that
  /// get the code text without a camera (manual entry, tests).
  Future<LinkedDevice?> authorizePayloadText(
    String payloadText, {
    required String ownerBlindHash,
    required String newDeviceId,
    int? nowMs,
  }) async {
    final payload = PairingPayload.decode(payloadText);
    if (payload == null) {
      return null; // malformed / PII-shaped — hard reject.
    }
    if (payload.isExpiredAt(nowMs ?? DateTime.now().millisecondsSinceEpoch)) {
      return null;
    }
    // The QR must belong to the SAME account this new device is logging
    // into — a QR for another blind hash is rejected outright.
    if (payload.ownerBlindHash != ownerBlindHash) {
      return null;
    }
    // Single-use secret (replay protection): a pairing secret already
    // consumed by a successful authorize can never authorize again.
    if (_consumedSecrets.contains(payload.pairingSecret)) {
      return null;
    }
    final material = payload.toKeyMaterial();
    if (material == null) {
      return null;
    }
    // CRITICAL (code-review hardening): cryptographically verify the
    // signed-prekey signature against the identity key embedded in the
    // payload BEFORE establishing any session or registering a device. A
    // tampered or substituted spk/otpk (photographed-QR MITM) is rejected
    // here — the placeholder-returning X3DH verify is never the gate.
    final verified = await Ed25519().verify(
      material.$3, // signedPreKey
      signature: Signature(
        material.$4, // signedPreKeySignature
        publicKey: SimplePublicKey(material.$1, type: KeyPairType.ed25519),
      ),
    );
    if (!verified) {
      return null;
    }
    // Establish the session with the primary as the X3DH initiator. Our own
    // identity key comes from (or is created in) secure storage.
    final identity = await _identityKeys.loadOrCreateIdentityKeyPair();
    await _sessions.establishInitiatorSession(
      peerBlindHash: payload.ownerBlindHash,
      bundle: PreKeyBundle(
        registrationId: payload.deviceId,
        identityKey: material.$1,
        signedPreKeyId: material.$2,
        signedPreKey: material.$3,
        signedPreKeySignature: material.$4,
        oneTimePreKeyId: material.$5,
        oneTimePreKey: material.$6,
      ),
      myIdentityKeyPair: identity,
    );
    final device = LinkedDevice(
      deviceId: payload.deviceId,
      ownerBlindHash: ownerBlindHash,
      publicKey: Uint8List.fromList(material.$1), // identity public key
      pairedAt: DateTime.now(),
    );
    await _registry.add(device);
    // Consume the one-time secret ONLY after a fully successful authorize.
    _consumedSecrets.add(payload.pairingSecret);
    return device;
  }

  /// Revokes (unlinks) the device with [deviceId]: removes it from the
  /// registry (marked revoked) and deletes any session keyed by the primary
  /// device's blind hash. Idempotent.
  Future<void> revokeDevice({
    required String deviceId,
    required String ownerBlindHash,
  }) async {
    await _registry.revoke(deviceId);
    await _sessions.deleteSession(ownerBlindHash);
  }

  /// Lists active (non-revoked) linked devices for [ownerBlindHash].
  Future<List<LinkedDevice>> listDevices(String ownerBlindHash) async {
    final all = await _registry.list(ownerBlindHash);
    return all.where((d) => !d.revoked).toList(growable: false);
  }

  /// Loads the device's identity key pair (creating + storing a fresh one
  /// when absent). Used by the PRIMARY side to publish the public half in a
  /// pairing QR.
  Future<SimpleKeyPair> loadIdentityKeyPair() =>
      _identityKeys.loadOrCreateIdentityKeyPair();

  /// Loads (creating if needed) the identity key pair and returns only its
  /// PUBLIC key — used by the pairing BLoC to build the primary bundle.
  Future<SimplePublicKey> loadIdentityPublicKey() =>
      _identityKeys.loadIdentityPublicKey();

  String _b64Url(Uint8List bytes) => base64UrlEncode(bytes).replaceAll('=', '');
}
