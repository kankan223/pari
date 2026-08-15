/// Port (domain boundary) for the one-way hash used by hash-only logging.
///
/// Hash-only logging means a sensitive value is NEVER written anywhere;
/// only an irreversible digest of it is. The digest is one-way (preimage
/// resistant), so the raw value cannot be recovered from the log.
///
/// Clean Architecture: the domain depends only on this abstract interface.
/// A SHA-256 implementation (from the `cryptography` package) lives in the
/// data layer and is injected at composition time; tests inject a stub.
abstract class HashProvider {
  /// Returns the hex-encoded SHA-256 digest of [input] (64 lowercase hex).
  ///
  /// Security: this is a ONE-WAY function. The original [input] must never
  /// be written to a log — only its return value may be.
  Future<String> sha256Hex(String input);
}
