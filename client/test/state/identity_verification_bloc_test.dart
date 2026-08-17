import 'package:civic_commons/identity/civic_pillar.dart';
import 'package:civic_commons/identity/pillar_claim_sources.dart';
import 'package:civic_commons/identity/pillar_claims.dart';
import 'package:civic_commons/identity/unified_identity_service.dart';
import 'package:civic_commons/state/data/local_identity_verification_bloc.dart';
import 'package:civic_commons/state/domain/identity_verification_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 10.1 — identity verification BLoC tests.
void main() {
  const validHash =
      '3f9c2b8d1a4e7f0a6c5b9d2e8f1a4c7b0d3e5f8a2b6c9d1e4f7a0b3c6e9d2f5a';

  LocalIdentityVerificationBloc verifiedBloc({String? hash = validHash}) {
    return LocalIdentityVerificationBloc(
      service: _FakeUnifiedIdentityService(hash),
      sources: MemoryPillarClaimSources(
        usernames: {validHash: 'savitri'},
        pinCodes: {validHash: '800001'},
        karma: {validHash: '247'},
      ),
    );
  }

  test('verify transitions loading → verified with per-pillar claims',
      () async {
    final bloc = verifiedBloc();
    final states = <IdentityVerificationState>[];
    final sub = bloc.state.listen(states.add);

    await bloc.verify();
    await Future<void>.delayed(Duration.zero);

    expect(states.first.isLoading, isTrue);
    final verified = states.last;
    expect(verified.isVerified, isTrue);
    expect(verified.blindHashId, validHash);
    expect(verified.displayHandle, '@citizen_3f9c2b');
    expect(verified.pillarClaims[CivicPillar.vault]!.username, 'savitri');
    expect(verified.pillarClaims[CivicPillar.ledger]!.pinCode, '800001');
    expect(verified.pillarClaims[CivicPillar.warRoom]!.heldClaims, isEmpty);
    expect(verified.pillarClaims[CivicPillar.academy]!.heldClaims, isEmpty);

    await sub.cancel();
    await bloc.close();
  });

  test('no identity → noIdentity state', () async {
    final bloc = verifiedBloc(hash: null);
    final states = <IdentityVerificationState>[];
    final sub = bloc.state.listen(states.add);

    await bloc.verify();
    await Future<void>.delayed(Duration.zero);

    expect(states.last.isNoIdentity, isTrue);
    expect(states.last.blindHashId, isNull);

    await sub.cancel();
    await bloc.close();
  });

  test('service failure → generic error state (payload-free)', () async {
    final bloc = LocalIdentityVerificationBloc(
      service: _FailingIdentityService(),
      sources: MemoryPillarClaimSources(),
    );
    final states = <IdentityVerificationState>[];
    final sub = bloc.state.listen(states.add);

    await bloc.verify();
    await Future<void>.delayed(Duration.zero);

    final error = states.last;
    expect(error.isError, isTrue);
    expect(error.errorMessage, isNotNull);
    expect(error.blindHashId, isNull);
    expect(error.pillarClaims, isEmpty);

    await sub.cancel();
    await bloc.close();
  });

  test('current returns the latest state for late subscribers', () async {
    final bloc = verifiedBloc();
    expect(bloc.current.isIdle, isTrue);
    await bloc.verify();
    await Future<void>.delayed(Duration.zero);
    expect(bloc.current.isVerified, isTrue);
    await bloc.close();
  });
}

class _FakeUnifiedIdentityService implements UnifiedIdentityService {
  final String? _hash;

  _FakeUnifiedIdentityService(this._hash);

  @override
  Future<String?> blindHashId() async => _hash;

  @override
  Future<PillarClaims?> claimsFor(CivicPillar pillar) async => null;

  @override
  Future<bool> hasIdentity() async => _hash != null;
}

class _FailingIdentityService implements UnifiedIdentityService {
  @override
  Future<String?> blindHashId() async => throw StateError('source down');

  @override
  Future<PillarClaims?> claimsFor(CivicPillar pillar) async => null;

  @override
  Future<bool> hasIdentity() async => throw StateError('source down');
}
