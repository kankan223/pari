import 'civic_pillar.dart';
import 'pillar_claims.dart';

/// Port for the local claim sources the Unified Identity Layer composes at
/// the edges (Task 10.1 — PRD §9.1).
///
/// Each pillar attribute lives in its OWN pillar store; the unified layer
/// only ever READS the minimum claim a pillar requests. No source here is a
/// "profile" — the sources are the existing pillar data (the Vault's
/// username directory + linked-device registry, the Ledger's pin-code scope
/// + karma cache). The production implementation wires those stores; the
/// harness/tests use an in-memory fake.
///
/// SECURITY CHECKPOINT (Task 10.1): this port never touches a phone number,
/// a raw private key, or a full blind-hash profile — only public pillar
/// attributes.
abstract class PillarClaimSources {
  /// The public username for [blindHashId] (Vault), or null.
  Future<String?> usernameFor(String blindHashId);

  /// The linked device PUBLIC keys for [blindHashId] (Vault), or empty.
  Future<List<String>> deviceKeysFor(String blindHashId);

  /// The coarse civic pin-code scope for [blindHashId] (Ledger), or null.
  Future<String?> pinCodeFor(String blindHashId);

  /// The public karma score for [blindHashId] (Ledger), or null.
  Future<String?> karmaFor(String blindHashId);
}

/// In-memory [PillarClaimSources] for the harness + tests (Task 10.1).
class MemoryPillarClaimSources implements PillarClaimSources {
  final Map<String, String> _usernames;
  final Map<String, List<String>> _deviceKeys;
  final Map<String, String> _pinCodes;
  final Map<String, String> _karma;

  MemoryPillarClaimSources({
    Map<String, String> usernames = const {},
    Map<String, List<String>> deviceKeys = const {},
    Map<String, String> pinCodes = const {},
    Map<String, String> karma = const {},
  })  : _usernames = usernames,
        _deviceKeys = deviceKeys,
        _pinCodes = pinCodes,
        _karma = karma;

  @override
  Future<String?> usernameFor(String blindHashId) async =>
      _usernames[blindHashId];

  @override
  Future<List<String>> deviceKeysFor(String blindHashId) async =>
      List.unmodifiable(_deviceKeys[blindHashId] ?? const []);

  @override
  Future<String?> pinCodeFor(String blindHashId) async =>
      _pinCodes[blindHashId];

  @override
  Future<String?> karmaFor(String blindHashId) async => _karma[blindHashId];
}

/// Convenience helper: composes the minimum claims for every pillar from
/// [sources] (used by the service + the verification UI).
Future<Map<CivicPillar, PillarClaims>> composeAllClaims({
  required String blindHashId,
  required PillarClaimSources sources,
}) async {
  final username = await sources.usernameFor(blindHashId);
  final deviceKeys = await sources.deviceKeysFor(blindHashId);
  final pinCode = await sources.pinCodeFor(blindHashId);
  final karma = await sources.karmaFor(blindHashId);

  return {
    CivicPillar.vault: PillarClaims.compose(
      pillar: CivicPillar.vault,
      blindHashId: blindHashId,
      username: username,
      deviceKeys: deviceKeys,
    ),
    CivicPillar.ledger: PillarClaims.compose(
      pillar: CivicPillar.ledger,
      blindHashId: blindHashId,
      pinCode: pinCode,
      karma: karma,
    ),
    CivicPillar.warRoom: PillarClaims.compose(
      pillar: CivicPillar.warRoom,
      blindHashId: blindHashId,
    ),
    CivicPillar.academy: PillarClaims.compose(
      pillar: CivicPillar.academy,
      blindHashId: blindHashId,
    ),
  };
}
