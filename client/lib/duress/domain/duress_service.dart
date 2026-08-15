import 'dart:typed_data';

import 'vault_database.dart';

/// Classification of the vault opened after a successful unlock.
///
/// This is a *runtime* classification produced solely by which database the
/// entered PIN successfully decrypts. It is computed in memory and is never
/// persisted anywhere (no file, no flag, no boolean, no storage key).
enum VaultKind {
  /// The real vault (`vault.db`) — opened by the real PIN.
  real,

  /// The decoy vault (`vault_decoy.db`) — opened by the duress PIN.
  decoy,
}

/// Result of a successful vault unlock.
class UnlockResult {
  /// Which vault was opened (real or decoy), derived from decryption success.
  final VaultKind kind;

  /// The database that the PIN successfully decrypted.
  final VaultDatabase database;

  /// The 32-byte session key (held in memory only, never persisted).
  final Uint8List key;

  const UnlockResult({
    required this.kind,
    required this.database,
    required this.key,
  });
}

/// Thrown when an entered PIN cannot decrypt either vault.
///
/// The same error is thrown regardless of whether the PIN was close to the
/// real or duress PIN — the service never reveals which vault a wrong PIN
/// "almost" matched.
class DuressPinException implements Exception {
  final String message;

  const DuressPinException(this.message);

  @override
  String toString() => 'DuressPinException: $message';
}

/// Thrown when PIN registration fails (e.g. PINs already registered, or the
/// real and duress PINs are identical).
class DuressRegistrationException implements Exception {
  final String message;

  const DuressRegistrationException(this.message);

  @override
  String toString() => 'DuressRegistrationException: $message';
}

/// Port (domain use case) for the duress PIN flow.
///
/// Responsibilities:
/// 1. Dual PIN registration (real PIN + duress PIN).
/// 2. Two independent Argon2id key derivation paths (one per PIN/salt),
///    each yielding a 256-bit database key.
/// 3. Decoy database initialization.
/// 4. Database selection based *solely* on which PIN successfully decrypts.
///
/// Security contract:
/// - The service never persists, logs, or stores any flag, boolean, or
///   indicator of which PIN is the real one versus the duress one.
abstract class DuressService {
  /// Registers the real and duress PINs.
  ///
  /// Both databases (`vault.db` and `vault_decoy.db`) are initialized as
  /// structurally identical, valid encrypted databases. Each PIN gets its own
  /// random Argon2id salt, producing two independent 256-bit database keys.
  ///
  /// Throws:
  /// - [ArgumentError] if a PIN is empty
  /// - [DuressRegistrationException] if PINs are identical or already registered
  Future<void> registerPins({
    required String realPin,
    required String duressPin,
  });

  /// Attempts to unlock a vault with the entered PIN.
  ///
  /// Selection is performed purely by decryption: the PIN's derived key is
  /// tried against each vault in turn, and the first vault it successfully
  /// decrypts is returned. No stored indicator is consulted.
  ///
  /// Returns: an [UnlockResult] describing which vault was opened.
  ///
  /// Throws:
  /// - [ArgumentError] if the PIN is empty
  /// - [DuressPinException] if the PIN cannot decrypt either vault
  Future<UnlockResult> unlock(String pin);

  /// Returns true if both vaults have been registered/initialized.
  Future<bool> isRegistered();
}
