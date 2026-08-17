import 'package:civic_commons/identity/civic_pillar.dart';
import 'package:civic_commons/identity/pillar_claim_sources.dart';
import 'package:civic_commons/identity/pillar_claims.dart';
import 'package:civic_commons/identity/unified_identity_service.dart';
import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_identity_verification_bloc.dart';
import 'package:civic_commons/state/ui/identity_verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSecureFlagService implements SecureFlagService {
  bool enabled = false;

  @override
  Future<void> enableSecureFlag() async => enabled = true;

  @override
  Future<void> disableSecureFlag() async => enabled = false;

  @override
  Future<bool> isSecureFlagSupported() async => true;
}

/// Task 10.1 — identity verification screen widget tests.
void main() {
  const validHash =
      '3f9c2b8d1a4e7f0a6c5b9d2e8f1a4c7b0d3e5f8a2b6c9d1e4f7a0b3c6e9d2f5a';
  LocalIdentityVerificationBloc verifiedBloc() => LocalIdentityVerificationBloc(
        service: _FakeIdentityService(validHash),
        sources: MemoryPillarClaimSources(
          usernames: {validHash: 'savitri'},
          deviceKeys: {
            validHash: ['pub-key-1']
          },
          pinCodes: {validHash: '800001'},
          karma: {validHash: '247'},
        ),
      );

  LocalIdentityVerificationBloc noIdentityBloc() =>
      LocalIdentityVerificationBloc(
        service: _FakeIdentityService(null),
        sources: MemoryPillarClaimSources(),
      );

  testWidgets('verified state renders the blinded handle + per-pillar rows',
      (tester) async {
    final flag = FakeSecureFlagService();
    await tester.pumpWidget(
      MaterialApp(
        home: IdentityVerificationScreen(
          bloc: verifiedBloc(),
          secureFlagService: flag,
        ),
      ),
    );
    await tester.pump(); // loading
    await tester.pump(); // verified (claims resolve synchronously)

    expect(find.text('❧ CIVIC COMMONS'), findsOneWidget);
    expect(find.text('IDENTITY VERIFIED'), findsOneWidget);
    expect(find.text('@citizen_3f9c2b'), findsOneWidget);
    // Per-pillar rows with fixed labels.
    expect(find.text('🔒  The Vault'), findsOneWidget);
    expect(find.text('📰  The Daily Ledger'), findsOneWidget);
    expect(find.text('🛡  The War Room'), findsOneWidget);
    expect(find.text('🎓  The Academy'), findsOneWidget);
    // Minimum claims: Vault username + device keys chip; Ledger pin + karma.
    expect(find.text('username'), findsOneWidget);
    expect(find.text('device keys'), findsOneWidget);
    expect(find.text('pin code'), findsOneWidget);
    expect(find.text('karma'), findsOneWidget);
    // War Room + Academy hold nothing beyond the hash.
    expect(find.text('identity only'), findsNWidgets(2));
    // FLAG_SECURE activated on mount.
    expect(flag.enabled, isTrue);
  });

  testWidgets('no identity state renders the onboarding prompt',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: IdentityVerificationScreen(bloc: noIdentityBloc())),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('NO IDENTITY YET'), findsOneWidget);
    expect(find.textContaining('never stored'), findsOneWidget);
    expect(find.text('IDENTITY VERIFIED'), findsNothing);
  });

  testWidgets('error state renders generic copy, zero payload', (tester) async {
    final bloc = LocalIdentityVerificationBloc(
      service: _FailingIdentityService(),
      sources: MemoryPillarClaimSources(),
    );
    await tester.pumpWidget(
      MaterialApp(home: IdentityVerificationScreen(bloc: bloc)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('VERIFICATION UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('Please try again'), findsOneWidget);
    expect(find.text('IDENTITY VERIFIED'), findsNothing);
  });

  testWidgets('onVerified host seam fires on CONTINUE', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: IdentityVerificationScreen(
          bloc: verifiedBloc(),
          onVerified: () => confirmed = true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('CONTINUE TO CIVIC COMMONS'));
    await tester.pump();
    expect(confirmed, isTrue);
  });

  testWidgets('zero-PII: no full 64-hex hash ever renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: IdentityVerificationScreen(bloc: verifiedBloc())),
    );
    await tester.pump();
    await tester.pump();

    // The full hash never appears anywhere in the tree (the screen only
    // renders the blinded @citizen_ fragment).
    expect(find.text(validHash), findsNothing);
    expect(find.textContaining(validHash.substring(0, 20)), findsNothing);
    // No phone-shaped literals either.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(texts.contains('+91'), isFalse);
    expect(texts.contains(RegExp(r'\+\d{10,}')), isFalse);
  });
}

class _FakeIdentityService implements UnifiedIdentityService {
  final String? _hash;

  _FakeIdentityService(this._hash);

  @override
  Future<String?> blindHashId() async => _hash;

  @override
  Future<bool> hasIdentity() async => _hash != null;

  @override
  Future<PillarClaims?> claimsFor(CivicPillar pillar) async => null;
}

class _FailingIdentityService implements UnifiedIdentityService {
  @override
  Future<String?> blindHashId() async => throw StateError('down');

  @override
  Future<bool> hasIdentity() async => throw StateError('down');

  @override
  Future<PillarClaims?> claimsFor(CivicPillar pillar) async => null;
}
