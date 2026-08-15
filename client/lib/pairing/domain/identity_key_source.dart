import 'package:cryptography/cryptography.dart';

/// Source of the device's X3DH/identity key pair (Task 6.5).
///
/// The pairing service needs the PUBLIC half to build a pairing QR and the
/// full pair to run X3DH on the new device. This port keeps the pairing
/// domain clean of concrete storage implementations; the data layer backs it
/// with [SecureKeyStorage] + [CryptoService] (hardware keystore).
///
/// SECURITY CHECKPOINT (Task 6.5): the private key never leaves this
/// abstraction's implementations and never enters the pairing payload.
abstract class IdentityKeySource {
  /// Loads the identity key pair from secure storage, creating and storing a
  /// fresh one when absent.
  Future<SimpleKeyPair> loadOrCreateIdentityKeyPair();

  /// The PUBLIC half of the identity key (for QR bundles).
  Future<SimplePublicKey> loadIdentityPublicKey();
}
