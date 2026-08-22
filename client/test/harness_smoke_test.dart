import 'package:civic_commons/auth/auth_bloc.dart';
import 'package:civic_commons/auth/auth_storage.dart';
import 'package:civic_commons/auth/identity_api_client.dart';
import 'package:civic_commons/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke test for the MANUAL TESTING HARNESS entry point
/// (client/lib/main.dart, Task: lib/main.dart entry point).
///
/// Builds the full in-memory dependency graph (including the Argon2id key
/// derivation, which needs REAL async — hence [WidgetTester.runAsync]) and
/// pumps the Material 3 shell, then verifies each of the four pillar
/// destinations mounts and renders without throwing — the fastest
/// catch-all for wiring regressions (bloc streams, navigators, seeded
/// data, FLAG_SECURE wrappers).
void main() {
  testWidgets('harness builds and renders all four destinations',
      (tester) async {
    // The unified identity layer (Task 10.1) persists the blind hash via
    // flutter_secure_storage — mock the channel so the harness build runs
    // plugin-free in tests (the real keychain is exercised on-device).
    FlutterSecureStorage.setMockInitialValues({});
    final harness = await tester.runAsync(HarnessDependencies.build);
    expect(harness, isNotNull);

    // Create a mock auth bloc that starts authenticated.
    // Pre-populate secure storage so init() sees a username and emits
    // authenticated state (username claim is now mandatory).
    final storage = AuthStorage();
    await storage.saveAuthTokens(
      accessToken: 'test-token',
      refreshToken: 'test-refresh',
      blindHashId: 'test-hash',
    );
    await storage.saveUsername('testuser');
    final authBloc = AuthBloc(
      api: IdentityApiClient(
        baseUrl: 'http://localhost:9999'),
      storage: storage,
    );
    await authBloc.init();

    await tester.pumpWidget(CivicCommonsHarness(
      harness: harness!,
      authBloc: authBloc,
    ));
    // Explicit pumps instead of pumpAndSettle: the harness screens run
    // real (never-ending) SecureScreenWrapper/status animations in test
    // mode, so settling would never complete. A few extra cycles let the
    // screens' initState-triggered bloc re-emits (start/refresh) land on
    // the broadcast streams.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // War Room tab is selected by default — the seeded case list renders.
    expect(find.text('▌WAR ROOM▐'), findsOneWidget);
    expect(find.text('CASE #CC-0047'), findsOneWidget);

    // Vault destination.
    await tester.tap(find.text('Vault'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('CONVERSATIONS'), findsOneWidget);
    expect(find.text('@savitri'), findsOneWidget);

    // Ledger destination.
    await tester.tap(find.text('Ledger'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Drainage repair deadline slips again'), findsOneWidget);

    // Academy destination.
    await tester.tap(find.text('Academy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('❧ THE ACADEMY'), findsOneWidget);

    // Unified Identity destination (Task 10.1).
    await tester.tap(find.text('Identity'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('❧ CIVIC COMMONS'), findsOneWidget);
    expect(find.text('IDENTITY VERIFIED'), findsOneWidget);
    expect(find.textContaining('@citizen_'), findsOneWidget);

    // Civic Karma destination (Task 10.2).
    await tester.tap(find.text('Karma'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('KARMA'), findsOneWidget);
    // Seeded ledger reaches exactly 247 (matches the identity screen's
    // karma claim) — the balance renders with the tier label.
    expect(find.text('247'), findsOneWidget);
    expect(find.textContaining('tier'), findsOneWidget);

    // Notification System destination (Task 10.4).
    await tester.tap(find.text('Alerts'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 5 seeded notifications: 3 unread + 2 read.
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Karma +5'), findsOneWidget);
    expect(find.text('Case CC-0047 assigned'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);

    // DPDP Consent destination (Task 11.1).
    await tester.tap(find.text('Consent'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Data Protection Consent'), findsOneWidget);
    expect(find.text('DIGITAL PERSONAL DATA PROTECTION'), findsOneWidget);
    expect(find.text('Core Platform Functionality'), findsOneWidget);

    // Performance Monitor destination (Task 12.1).
    await tester.tap(find.text('Perf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('PERFORMANCE MONITOR'), findsOneWidget);
    expect(find.text('STARTUP TIMES'), findsOneWidget);
    expect(find.text('MEMORY USAGE'), findsOneWidget);
  });
}
