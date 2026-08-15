import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// One-time pairing secret generator (Task 6.5).
///
/// The secret is 32 random bytes from a cryptographically secure RNG,
/// base64url-encoded (43 chars, unpadded). It is embedded in the QR payload
/// and proves the scanner PHYSICALLY holds the QR — it is single-use,
/// short-lived, and never persisted or logged.
///
/// SECURITY CHECKPOINT (Task 6.5): the secret carries zero identity data —
/// it is pure entropy, so it can never be a PII carrier.
class PairingSecretGenerator {
  final Random _random;

  PairingSecretGenerator({Random? random})
      : _random = random ?? Random.secure();

  /// Generates a fresh 32-byte base64url secret.
  ///
  /// A deterministic [Random] may be injected for tests only.
  String generate() {
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
