import 'dart:typed_data';

import 'package:civic_commons/duress/data/duress_service_impl.dart';
import 'package:civic_commons/duress/domain/duress_service.dart';
import 'package:civic_commons/duress/domain/vault_database.dart';
import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_duress_setup_bloc.dart';
import 'package:civic_commons/state/ui/duress_pin_setup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 6.6): [DuressPinSetupSheet] registers the real + duress PIN
/// pair (the ONE screen that labels them — onboarding), shows a generic
/// error for identical PINs, obscures both fields, and enables FLAG_SECURE.
void main() {
  group('DuressPinSetupSheet - onboarding registration', () {
    late _FakeDuressService service;
    late LocalDuressSetupBloc bloc;
    var registered = false;

    setUp(() {
      service = _FakeDuressService();
      bloc = LocalDuressSetupBloc(service: service);
      registered = false;
    });

    tearDown(() => bloc.close());

    Future<void> pumpSheet(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DuressPinSetupSheet(
            bloc: bloc,
            onRegistered: () => registered = true,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('renders two obscured PIN fields and a register button',
        (tester) async {
      await pumpSheet(tester);

      expect(find.text('SET UP VAULT PINs'), findsOneWidget);
      final fields =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields, hasLength(2));
      expect(fields.every((f) => f.obscureText), isTrue,
          reason: 'both PIN fields must be obscured');
      expect(
          find.widgetWithText(FilledButton, 'Register PINs'), findsOneWidget);
    });

    testWidgets('registering valid distinct PINs calls onRegistered',
        (tester) async {
      await pumpSheet(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '123456');
      await tester.enterText(fields.at(1), '654321');
      await tester.tap(find.text('Register PINs'));
      await tester.pump();
      await tester.pump();

      expect(registered, isTrue);
      expect(await service.isRegistered(), isTrue);
    });

    testWidgets('identical PINs show the generic error and register nothing',
        (tester) async {
      await pumpSheet(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '111111');
      await tester.enterText(fields.at(1), '111111');
      await tester.tap(find.text('Register PINs'));
      await tester.pump();
      await tester.pump();

      expect(registered, isFalse);
      expect(await service.isRegistered(), isFalse);
      expect(find.text('PINs could not be registered. Please try again.'),
          findsOneWidget);
    });
  });

  group('DuressPinSetupSheet - FLAG_SECURE + PII (Task 6.6)', () {
    testWidgets('enables FLAG_SECURE on mount', (tester) async {
      final flag = _RecordingFlagService();
      final bloc = LocalDuressSetupBloc(service: _FakeDuressService());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DuressPinSetupSheet(
            bloc: bloc,
            onRegistered: () {},
            secureFlagService: flag,
          ),
        ),
      ));
      await tester.pump();

      expect(flag.enableCalls, 1);

      await bloc.close();
    });

    testWidgets('the entered PINs never render as text', (tester) async {
      final bloc = LocalDuressSetupBloc(service: _FakeDuressService());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DuressPinSetupSheet(bloc: bloc, onRegistered: () {}),
        ),
      ));
      await tester.pump();
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '123456');
      await tester.enterText(fields.at(1), '654321');
      await tester.pump();

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(texts, isNot(contains('123456')));
      expect(texts, isNot(contains('654321')));

      await bloc.close();
    });
  });
}

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

/// In-memory [DuressService] fake for the setup state machine.
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
    if (realPin.isEmpty || duressPin.isEmpty) {
      throw ArgumentError('PINs cannot be empty');
    }
    if (realPin == duressPin) {
      throw const DuressRegistrationException(
          'Real and duress PINs must be different');
    }
    if (this.realPin != null) {
      throw const DuressRegistrationException('PINs are already registered');
    }
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
