import 'package:civic_commons/auth/auth_bloc.dart';
import 'package:civic_commons/auth/auth_storage.dart';
import 'package:civic_commons/auth/identity_api_client.dart';
import 'package:civic_commons/main.dart';
import 'package:civic_commons/repository/data/memory_user_search_repository.dart';
import 'package:civic_commons/state/data/local_user_search_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke test for the MANUAL TESTING HARNESS entry point
/// (client/lib/main.dart, Task: lib/main.dart entry point).
///
/// Builds the full in-memory dependency graph (including the Argon2id key
/// derivation, which needs REAL async — hence [WidgetTester.runAsync]) and
/// pumps the Material 3 shell, then verifies onboarding and each of the
/// five core destinations mounts and renders without throwing.
void main() {
  testWidgets('harness builds and renders all five destinations',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final harness = await tester.runAsync(HarnessDependencies.build);
    expect(harness, isNotNull);

    final storage = AuthStorage();
    await storage.saveAuthTokens(
      accessToken: 'test-token',
      refreshToken: 'test-refresh',
      blindHashId: 'test-hash',
    );
    await storage.saveUsername('testuser');
    final authBloc = AuthBloc(
      api: IdentityApiClient(baseUrl: 'http://localhost:9999'),
      storage: storage,
    );
    await authBloc.init();

    await tester.pumpWidget(CivicCommonsHarness(
      harness: harness!,
      authBloc: authBloc,
      userSearchBloc: LocalUserSearchBloc(
        repository: MemoryUserSearchRepository(),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Onboarding shows first — tap Skip to dismiss.
    expect(find.text('Privacy First'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Home tab is selected by default — the dashboard renders.
    expect(find.textContaining('Good'), findsOneWidget);

    // Messages destination (use last match - navigation bar).
    final msgFinds = find.text('Messages');
    await tester.tap(msgFinds.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('CONVERSATIONS'), findsOneWidget);

    // Community destination.
    final communityFinds = find.text('Community');
    await tester.tap(communityFinds.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Drainage repair deadline slips again'), findsOneWidget);

    // Learn destination.
    final learnFinds = find.text('Learn');
    await tester.tap(learnFinds.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('❧ THE ACADEMY'), findsOneWidget);

    // Profile destination.
    final profileFinds = find.text('Profile');
    await tester.tap(profileFinds.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });
}
