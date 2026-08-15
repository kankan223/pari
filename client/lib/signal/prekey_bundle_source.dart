import 'models.dart';

/// Port for fetching a peer's published X3DH prekey bundle (Task 6.3).
///
/// The bundle carries only PUBLIC keys — never private material. Lookups are
/// keyed by the peer's 64-hex blind hash; returning null means "no bundle
/// published" (peer not registered, or not yet synced) — the caller must
/// degrade gracefully rather than fail.
abstract class PreKeyBundleSource {
  /// The peer's published [PreKeyBundle], or null when none is available.
  Future<PreKeyBundle?> fetchFor(String peerBlindHash);
}

/// In-memory [PreKeyBundleSource] — a registry seeded locally (dev/tests).
///
/// SECURITY CHECKPOINT (Task 6.3): keys are blind hashes; values carry only
/// public key material. Nothing is logged or persisted in plaintext.
class InMemoryPreKeyBundleSource implements PreKeyBundleSource {
  final Map<String, PreKeyBundle> _bundles = {};

  /// Publishes [bundle] for [peerBlindHash] (replaces any existing).
  void publish(String peerBlindHash, PreKeyBundle bundle) {
    _bundles[peerBlindHash] = bundle;
  }

  @override
  Future<PreKeyBundle?> fetchFor(String peerBlindHash) async =>
      _bundles[peerBlindHash];
}
