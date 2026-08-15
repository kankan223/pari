import 'dart:convert';
import 'dart:typed_data';

/// The QR payload that links a new device to this account (Task 6.5).
///
/// Carried PHYSICALLY via the QR code — never through cloud backup, never
/// through any sync transport. Contents:
/// - [ownerBlindHash]: the account's 64-hex blind hash (the ONLY identity).
/// - [deviceId]: the primary (showing) device's UUID v4.
/// - [pairingSecret]: a one-time 32-byte random secret (base64url) proving
///   the scanner physically holds the QR — single-use, short-lived.
/// - [expiresAtMs]: the payload's lifetime bound (default 5 minutes).
/// - Public key material ONLY: [identityKey], the signed prekey (id + key +
///   signature), and an optional one-time prekey. PRIVATE keys NEVER appear
///   here — this payload is shown on a screen and could be photographed.
///
/// SECURITY CONTRACT (Task 6.5):
///  - Zero PII: the only identity is a 64-hex blind hash. Phones, usernames,
///    e-mails, and private keys are structurally impossible — the codec
///    validates every field shape and rejects anything that does not match.
///  - One-time: the pairing secret + short expiry make a photographed QR
///    useless after the pairing window closes.
///  - Key transfer via QR, not cloud sync: the public key material travels
///    through the QR itself; nothing is backed up or uploaded.
class PairingPayload {
  /// Schema version of this payload (currently 1).
  final int version;

  final String ownerBlindHash;
  final String deviceId;

  /// One-time 32-byte random secret (base64url). Never persisted, never
  /// logged, single use.
  final String pairingSecret;

  /// Epoch milliseconds after which the payload must not be accepted.
  final int expiresAtMs;

  // Public key material (all base64url-encoded bytes).
  final String identityKey;
  final int signedPreKeyId;
  final String signedPreKey;
  final String signedPreKeySignature;
  final int? oneTimePreKeyId;
  final String? oneTimePreKey;

  const PairingPayload({
    this.version = 1,
    required this.ownerBlindHash,
    required this.deviceId,
    required this.pairingSecret,
    required this.expiresAtMs,
    required this.identityKey,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    this.oneTimePreKeyId,
    this.oneTimePreKey,
  });

  /// Whether the payload is still within its lifetime window.
  bool isExpiredAt(int nowMs) => nowMs > expiresAtMs;

  /// Encodes the payload into the compact URI used as the QR content.
  ///
  /// Format: `civic-commons://pair?v=1&bh=…&did=…&sec=…&exp=…&ik=…&spkid=…`
  /// `&spk=…&sig=…[&otpkid=…&otpk=…]` — every value URL-encoded so the QR
  /// bytes are strictly ASCII.
  String encode() {
    final b = StringBuffer('civic-commons://pair');
    b.write('?v=$version');
    b.write('&bh=$ownerBlindHash');
    b.write('&did=${Uri.encodeComponent(deviceId)}');
    b.write('&sec=$pairingSecret');
    b.write('&exp=$expiresAtMs');
    b.write('&ik=${Uri.encodeComponent(identityKey)}');
    b.write('&spkid=$signedPreKeyId');
    b.write('&spk=${Uri.encodeComponent(signedPreKey)}');
    b.write('&sig=${Uri.encodeComponent(signedPreKeySignature)}');
    if (oneTimePreKeyId != null && oneTimePreKey != null) {
      b.write('&otpkid=$oneTimePreKeyId');
      b.write('&otpk=${Uri.encodeComponent(oneTimePreKey!)}');
    }
    return b.toString();
  }

  /// Decodes and STRICTLY validates a QR payload string.
  ///
  /// Returns null when the payload is malformed, expired, or contains any
  /// field that is not exactly the expected shape (this is the boundary that
  /// guarantees PII can never be accepted as a pairing payload). Never
  /// throws for data failures.
  static PairingPayload? decode(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'civic-commons' || uri.host != 'pair') {
      return null;
    }
    final params = uri.queryParameters;
    final version = int.tryParse(params['v'] ?? '');
    if (version != 1) {
      return null;
    }
    final blindHash = params['bh'];
    final deviceId = params['did'];
    final secret = params['sec'];
    final exp = int.tryParse(params['exp'] ?? '');
    final ik = params['ik'];
    final spkId = int.tryParse(params['spkid'] ?? '');
    final spk = params['spk'];
    final sig = params['sig'];
    final otpkIdRaw = params['otpkid'];
    final otpkRaw = params['otpk'];
    if (blindHash == null ||
        deviceId == null ||
        secret == null ||
        exp == null ||
        ik == null ||
        spkId == null ||
        spk == null ||
        sig == null) {
      return null;
    }
    if (!isValidBlindHash(blindHash)) {
      return null;
    }
    if (!isValidUuidV4(deviceId)) {
      return null;
    }
    if (!isValidPairingSecret(secret)) {
      return null;
    }
    // Public keys must decode as bytes and match the X3DH wire sizes.
    if (!_isValidKey(ik) || !_isValidKey(spk) || !_isValidKey(sig)) {
      return null;
    }
    // One-time prekey: both id and key must be present together.
    if ((otpkIdRaw == null) != (otpkRaw == null)) {
      return null;
    }
    int? otpkId;
    String? otpk;
    if (otpkIdRaw != null && otpkRaw != null) {
      otpkId = int.tryParse(otpkIdRaw);
      if (otpkId == null || !_isValidKey(otpkRaw)) {
        return null;
      }
      otpk = otpkRaw;
    }
    return PairingPayload(
      ownerBlindHash: blindHash,
      deviceId: deviceId,
      pairingSecret: secret,
      expiresAtMs: exp,
      identityKey: ik,
      signedPreKeyId: spkId,
      signedPreKey: spk,
      signedPreKeySignature: sig,
      oneTimePreKeyId: otpkId,
      oneTimePreKey: otpk,
    );
  }

  /// Whether [value] is a 64-lowercase-hex blind hash — the ONLY identity
  /// the pairing flow transports.
  static bool isValidBlindHash(String value) =>
      _blindHashRegExp.hasMatch(value);

  static final RegExp _blindHashRegExp = RegExp(r'^[0-9a-f]{64}$');

  /// Strict RFC 4122 UUID v4 shape.
  static bool isValidUuidV4(String value) => _uuidV4RegExp.hasMatch(value);

  static final RegExp _uuidV4RegExp = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-'
    r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  /// Pairing secrets are exactly 32 random bytes, base64url (43 chars, no
  /// padding). This rejects any PII-shaped value outright.
  static bool isValidPairingSecret(String value) =>
      value.length == 43 && _base64UrlRegExp.hasMatch(value);

  static final RegExp _base64UrlRegExp = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Public keys are base64url-encoded byte strings of a fixed wire size
  /// (32-byte X25519/Ed25519 keys, 64-byte signatures). The decode also
  /// verifies the round-trip so garbage can never pass.
  static bool _isValidKey(String value) {
    if (!_base64UrlRegExp.hasMatch(value)) {
      return false;
    }
    try {
      final bytes = _b64UrlDecode(value);
      return bytes.length == 32 || bytes.length == 64;
    } on FormatException {
      return false;
    }
  }

  /// Decodes an UNPADDED base64url string (Dart's [base64Url.decode] requires
  /// a length that is a multiple of 4, so padding must be re-applied first).
  static Uint8List _b64UrlDecode(String value) {
    final pad = (4 - value.length % 4) % 4;
    return base64Url.decode(value + '=' * pad);
  }

  /// Builds a [PreKeyBundle]-compatible public key set from this payload
  /// (the scanner uses it to run X3DH with the primary device). Returns the
  /// raw key bytes, or null when a key is malformed.
  ///
  /// SECURITY: only public material is reconstructed — the payload never
  /// carried private keys in the first place.
  (Uint8List, int, Uint8List, Uint8List, int?, Uint8List?)? toKeyMaterial() {
    try {
      final otpk = oneTimePreKey;
      return (
        _b64UrlDecode(identityKey),
        signedPreKeyId,
        _b64UrlDecode(signedPreKey),
        _b64UrlDecode(signedPreKeySignature),
        otpk == null ? null : oneTimePreKeyId,
        otpk == null ? null : _b64UrlDecode(otpk),
      );
    } on FormatException {
      return null;
    }
  }
}
