import '../../signal/models.dart';

/// Result of fetching a peer's prekey bundle, including the remaining
/// one-time prekey count for replenishment monitoring.
class PreKeyBundleFetchResult {
  /// The peer's prekey bundle, or null if none published.
  final PreKeyBundle? bundle;

  /// Number of OTPKs remaining on the server after this fetch.
  /// Null if the server didn't include the count.
  final int? remainingOTPKs;

  const PreKeyBundleFetchResult({
    this.bundle,
    this.remainingOTPKs,
  });
}
