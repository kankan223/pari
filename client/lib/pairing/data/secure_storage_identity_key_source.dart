import 'package:cryptography/cryptography.dart';

import '../../crypto/crypto_service.dart';
import '../../crypto/secure_key_storage.dart';
import '../domain/identity_key_source.dart';

/// [IdentityKeySource] backed by the hardware keystore (data layer,
/// Task 6.5).
///
/// The private key lives only in [SecureKeyStorage] (Keychain/Keystore) and
/// is never logged, persisted in plaintext, or placed into a pairing QR.
class SecureStorageIdentityKeySource implements IdentityKeySource {
  final SecureKeyStorage _keyStorage;
  final CryptoService _crypto;

  SecureStorageIdentityKeySource({
    required SecureKeyStorage keyStorage,
    required CryptoService crypto,
  })  : _keyStorage = keyStorage,
        _crypto = crypto;

  @override
  Future<SimpleKeyPair> loadOrCreateIdentityKeyPair() async {
    return await _keyStorage.getIdentityKeyPair() ??
        await _createAndStoreIdentity();
  }

  @override
  Future<SimplePublicKey> loadIdentityPublicKey() async {
    final pair = await loadOrCreateIdentityKeyPair();
    return pair.extractPublicKey();
  }

  Future<SimpleKeyPair> _createAndStoreIdentity() async {
    final fresh = await _crypto.generateEd25519KeyPair();
    await _keyStorage.storeIdentityKeyPair(fresh);
    return fresh;
  }
}
