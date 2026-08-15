import 'package:cryptography/cryptography.dart';

import '../../crypto/crypto_service.dart';
import '../../crypto/secure_key_storage.dart';
import '../../signal/prekey_bundle_source.dart';
import '../../signal/session_manager.dart';
import '../domain/session_establisher.dart';

/// [SessionEstablisher] implementation (data layer, Task 6.3).
///
/// On approval of a connection request this:
/// 1. fetches the peer's published [PreKeyBundle] (blind-hash keyed),
/// 2. loads (or creates) our Ed25519 identity key pair from the hardware
///    keystore,
/// 3. runs X3DH as the initiator and stores the Double Ratchet session.
///
/// SECURITY CHECKPOINT (Task 6.3): all lookups are by 64-hex blind hash;
/// only public key material leaves the device (the published bundle); our
/// identity private key stays in secure storage and is never logged.
class LocalSessionEstablisher implements SessionEstablisher {
  final PreKeyBundleSource _bundleSource;
  final SessionManager _sessions;
  final SecureKeyStorage _keyStorage;
  final CryptoService _crypto;

  LocalSessionEstablisher({
    required PreKeyBundleSource bundleSource,
    required SessionManager sessions,
    required SecureKeyStorage keyStorage,
    required CryptoService crypto,
  })  : _bundleSource = bundleSource,
        _sessions = sessions,
        _keyStorage = keyStorage,
        _crypto = crypto;

  @override
  Future<void> establishWith(String peerBlindHash) async {
    // Idempotent: an existing session is reused (also makes repeated accepts
    // of the same peer harmless).
    if (await _sessions.hasSession(peerBlindHash)) {
      return;
    }
    final bundle = await _bundleSource.fetchFor(peerBlindHash);
    if (bundle == null) {
      throw StateError('No prekey bundle published for peer');
    }
    final identity = await _keyStorage.getIdentityKeyPair() ??
        await _createAndStoreIdentity();
    await _sessions.establishInitiatorSession(
      peerBlindHash: peerBlindHash,
      bundle: bundle,
      myIdentityKeyPair: identity,
    );
  }

  Future<SimpleKeyPair> _createAndStoreIdentity() async {
    final fresh = await _crypto.generateEd25519KeyPair();
    await _keyStorage.storeIdentityKeyPair(fresh);
    return fresh;
  }
}
