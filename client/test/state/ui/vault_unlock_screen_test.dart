import 'dart:typed_data';

import 'package:civic_commons/duress/data/duress_service_impl.dart';
import 'package:civic_commons/duress/domain/duress_service.dart';
import 'package:civic_commons/duress/domain/vault_database.dart';
import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_vault_unlock_bloc.dart';
import 'package:civic_commons/state/ui/vault_unlock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 6.6): [VaultUnlockScreen] is a single PIN prompt with
/// IDENTICAL presentation for the real and duress PINs — the only
/// difference is the [UnlockResult] delivered to the routing callback.
/// Wrong/empty PINs show one generic error; unregistered vaults offer the
/// setup path; FLAG_SECURE is enabled on mount.
void main() {
  group('VaultUnlockScreen - unlock flow', () {
    late _FakeDuressService service;
    late LocalVaultUnlockBloc bloc;
    UnlockResult? unlocked;

    setUp(() async {
      service = _FakeDuressService();
      await service.registerPins(realPin: '123456', duressPin: '654321');
      bloc = LocalVaultUnlockBloc(service: service);
      unlocked = null;
    });

    tearDown(() => bloc.close());

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: VaultUnlockScreen(
          bloc: bloc,
          onUnlocked: (r) => unlocked = r,
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('renders the masthead, an obscured PIN field, and Unlock',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('THE VAULT'), findsOneWidget);
      expect(find.text('ENTER PIN'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
    });

    testWidgets('real PIN routes the REAL vault to the callback',
        (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();

      expect(unlocked, isNotNull);
      expect(unlocked!.kind, VaultKind.real);
      expect(unlocked!.database.name, DuressServiceImpl.realVaultName);
    });

    testWidgets('duress PIN routes the DECOY vault to the callback',
        (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), '654321');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();

      expect(unlocked, isNotNull);
      expect(unlocked!.kind, VaultKind.decoy);
      expect(unlocked!.database.name, DuressServiceImpl.decoyVaultName);
    });

    testWidgets('wrong PIN shows the single generic error and routes nothing',
        (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();

      expect(unlocked, isNull);
      expect(find.text('Incorrect PIN. Please try again.'), findsOneWidget);
    });

    testWidgets('a PIN one digit off real vs one off duress shows identical UI',
        (tester) async {
      // Near-real PIN.
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), '123457');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();
      final nearRealText = _visibleTexts(tester);

      // Near-duress PIN (fresh screen, same bloc).
      await tester.pumpWidget(Container()); // unmount
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), '654322');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();
      final nearDuressText = _visibleTexts(tester);

      expect(nearDuressText, nearRealText,
          reason: 'failure UI must be byte-identical for both PIN types');
      expect(nearDuressText, contains('Incorrect PIN. Please try again.'));
    });
  });

  group('VaultUnlockScreen - not registered (onboarding path)', () {
    testWidgets('unregistered vault shows setup prompt instead of PIN field',
        (tester) async {
      final service = _FakeDuressService(); // never registered
      final bloc = LocalVaultUnlockBloc(service: service);
      var setupRequested = false;

      await tester.pumpWidget(MaterialApp(
        home: VaultUnlockScreen(
          bloc: bloc,
          onUnlocked: (_) {},
          onSetupRequired: () => setupRequested = true,
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('VAULT LOCK'), findsOneWidget);
      expect(find.text('Set up PINs'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Set up PINs'));
      await tester.pump();
      expect(setupRequested, isTrue);

      await bloc.close();
    });
  });

  group('VaultUnlockScreen - FLAG_SECURE (Task 6.6)', () {
    testWidgets('enables FLAG_SECURE on mount', (tester) async {
      final flag = _RecordingFlagService();
      final service = _FakeDuressService();
      await service.registerPins(realPin: '123456', duressPin: '654321');
      final bloc = LocalVaultUnlockBloc(service: service);

      await tester.pumpWidget(MaterialApp(
        home: VaultUnlockScreen(
          bloc: bloc,
          onUnlocked: (_) {},
          secureFlagService: flag,
        ),
      ));
      await tester.pump();

      expect(flag.enableCalls, 1,
          reason: 'mounting the unlock screen must enable FLAG_SECURE');

      await bloc.close();
    });

    testWidgets('renders no PII-shaped text', (tester) async {
      final service = _FakeDuressService();
      await service.registerPins(realPin: '123456', duressPin: '654321');
      final bloc = LocalVaultUnlockBloc(service: service);

      await tester.pumpWidget(MaterialApp(
        home: VaultUnlockScreen(bloc: bloc, onUnlocked: (_) {}),
      ));
      await tester.pump();
      await tester.pump();

      final texts = _visibleTexts(tester);
      expect(texts, isNot(contains('+91')));
      expect(texts, isNot(contains('hvs.')));
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      expect(texts, isNot(contains('123456')));
      expect(texts, isNot(contains('654321')));

      await bloc.close();
    });
  });
}

String _visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join('|');

class _RecordingFlagService implements SecureFlagService {
  int enableCalls = 0;

  @override
  Future<void> disableSecureFlag() async {}

  @override
  Future<void> enableSecureFlag() async {
    enableCalls++;
  }

  @override
  Future<bool> isSecureFlagSupported() async => true;
}

/// In-memory [DuressService] fake (see vault_unlock_bloc_test for the same
/// shape) so widget tests run without Argon2id.
class _FakeDuressService implements DuressService {
  String? realPin;
  String? duressPin;

  @override
  Future<bool> isRegistered() async => realPin != null;

  @override
  Future<void> registerPins({
    required String realPin,
    required String duressPin,
  }) async {
    this.realPin = realPin;
    this.duressPin = duressPin;
  }

  @override
  Future<UnlockResult> unlock(String pin) async {
    if (pin == realPin) {
      return UnlockResult(
        kind: VaultKind.real,
        database: _FakeVaultDatabase(DuressServiceImpl.realVaultName),
        key: Uint8List(32),
      );
    }
    if (pin == duressPin) {
      return UnlockResult(
        kind: VaultKind.decoy,
        database: _FakeVaultDatabase(DuressServiceImpl.decoyVaultName),
        key: Uint8List(32),
      );
    }
    throw const DuressPinException('PIN could not unlock any vault');
  }
}

class _FakeVaultDatabase implements VaultDatabase {
  @override
  final String name;
  _FakeVaultDatabase(this.name);

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<void> initialize({
    required Uint8List key,
    required Uint8List salt,
    List<VaultRecord> seedRecords = const [],
  }) async {}

  @override
  Future<bool> isInitialized() async => true;

  @override
  Future<Uint8List> readSalt() async => Uint8List(16);

  @override
  Future<List<VaultRecord>> readRecords(Uint8List key) async => const [];

  @override
  Future<bool> tryOpen(Uint8List key) async => true;

  @override
  Future<void> writeRecord(Uint8List key, VaultRecord record) async {}
}
