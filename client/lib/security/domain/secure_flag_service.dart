/// Port (domain use case) for the Android FLAG_SECURE screen-capture guard.
///
/// Responsibilities:
/// 1. Enable the platform `FLAG_SECURE` window flag so screenshots, screen
///    recording, and the Android recents preview cannot capture the content
///    rendered by a protected screen (Vault, War Room).
/// 2. Disable the flag when the protected screen is left.
/// 3. Report whether the platform actually supports the flag (graceful
///    degradation when it is unavailable — the app must keep working).
///
/// Clean Architecture: the domain layer depends only on this abstract
/// interface; a platform-channel implementation lives in the data layer and
/// is injected at composition time. Tests use an in-memory fake.
///
/// Security contract:
/// - Enabling FLAG_SECURE is a local OS-level operation. No screen content,
///   user data, or device fingerprinting information is ever transmitted.
abstract class SecureFlagService {
  /// Returns true when the platform can enforce FLAG_SECURE.
  ///
  /// On platforms without the flag (or without the native channel wired up)
  /// this must return false rather than throw, so protected screens can still
  /// render (degraded, but functional).
  Future<bool> isSecureFlagSupported();

  /// Enables FLAG_SECURE for the current window.
  ///
  /// Must be a no-op (not throw) when unsupported.
  Future<void> enableSecureFlag();

  /// Disables FLAG_SECURE for the current window.
  ///
  /// Must be a no-op (not throw) when unsupported.
  Future<void> disableSecureFlag();
}
