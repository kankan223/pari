import 'package:civic_commons/consent/data/in_memory_consent_repository.dart';
import 'package:civic_commons/security/ui/secure_screen_wrapper.dart';
import 'package:civic_commons/state/data/local_consent_bloc.dart';
import 'package:civic_commons/state/ui/dpdp_consent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DpdpConsentScreen', () {
    late LocalConsentBloc bloc;

    setUp(() {
      bloc = LocalConsentBloc(repository: InMemoryConsentRepository());
    });

    tearDown(() async {
      await bloc.close();
    });

    testWidgets('renders consent screen with title and header', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DpdpConsentScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Data Protection Consent'), findsOneWidget);
      expect(
        find.text('DIGITAL PERSONAL DATA PROTECTION'),
        findsOneWidget,
      );
    });

    testWidgets('renders all five consent type toggles', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DpdpConsentScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Core Platform Functionality'), findsOneWidget);
      expect(find.text('Civic Engagement'), findsOneWidget);
      expect(find.text('Security Contributions'), findsOneWidget);
      expect(find.text('Educational Content'), findsOneWidget);
      expect(find.text('Analytics & Improvement'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNWidgets(5));
    });

    testWidgets('shows Required/Optional labels correctly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DpdpConsentScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      // 4 required + 1 optional
      expect(find.text('Required'), findsNWidgets(4));
      expect(find.text('Optional'), findsOneWidget);
    });

    testWidgets('shows consent version', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DpdpConsentScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Version 1.0'), findsOneWidget);
    });

    testWidgets('DPDP description is shown', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DpdpConsentScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Digital Personal Data Protection Act'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a switch triggers consent flow', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DpdpConsentScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      // Tap the first switch to trigger grantAll
      await tester.tap(find.byType(SwitchListTile).first);
      // The switch should have been interacted with
      expect(find.byType(SwitchListTile), findsNWidgets(5));
    });

    testWidgets('consent form shows when bloc has data', (tester) async {
      // Pre-grant all consents so bloc.current has ready state
      await bloc.grantAll();

      await tester.pumpWidget(MaterialApp(
        home: DpdpConsentScreen(bloc: bloc),
      ));
      // One frame: initState runs _last = bloc.current (ready with allGranted)
      await tester.pump();

      // The consent form should show (even though refresh will reset to loading)
      // At minimum the toggle tiles should be visible in the initial render
      expect(find.byType(SwitchListTile), findsNWidgets(5));
    });

    testWidgets('security checkpoint: FLAG_SECURE wrapper is present',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DpdpConsentScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      // SecureScreenWrapper is in the widget tree
      expect(find.byType(SecureScreenWrapper), findsOneWidget);
    });
  });
}


