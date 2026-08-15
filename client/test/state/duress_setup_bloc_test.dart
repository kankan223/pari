import 'dart:typed_data';

import 'package:civic_commons/duress/data/duress_service_impl.dart';
import 'package:civic_commons/duress/domain/duress_service.dart';
import 'package:civic_commons/duress/domain/vault_database.dart';
import 'package:civic_commons/state/data/local_duress_setup_bloc.dart';
import 'package:civic_commons/state/domain/duress_setup_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 6.6): [LocalDuressSetupBloc] registers the real + duress
/// PIN pair and maps every failure to a GENERIC [DuressSetupPhase.failed] —
/// identical PINs, duplicate registration, and empty PINs are never
/// distinguished to the UI.
void main() {
  group('DuressSetupBloc - registration lifecycle', () {
    late _FakeDuressService service;
    late LocalDuressSetupBloc bloc;

    setUp(() {
      service = _FakeDuressService();
      bloc = LocalDuressSetupBloc(service: service);
    });

    tearDown(() => bloc.close());

    test('start emits idle', () async {
      final states = <DuressSetupState>[];
      bloc.state.listen(states.add);
      await bloc.start();
      expect(states, hasLength(1));
      expect(states.single.phase, DuressSetupPhase.idle);
      expect(states.single.hasError, isFalse);
    });

    test('register emits registering → registered and both PINs work',
        () async {
      final states = <DuressSetupState>[];
      bloc.state.listen(states.add);
      await bloc.start();

      await bloc.register(realPin: '123456', duressPin: '654321');

      expect(states.map((s) => s.phase), [
        DuressSetupPhase.idle,
        DuressSetupPhase.registering,
        DuressSetupPhase.registered,
      ]);
      expect(states.any((s) => s.hasError), isFalse);
      expect(await service.isRegistered(), isTrue);
      // Both PINs unlock (their respective vaults).
      expect((await service.unlock('123456')).kind, VaultKind.real);
      expect((await service.unlock('654321')).kind, VaultKind.decoy);
    });

    test('identical PINs → generic failed, nothing registered', () async {
      final states = <DuressSetupState>[];
      bloc.state.listen(states.add);

      await bloc.register(realPin: '111111', duressPin: '111111');

      expect(states.last.phase, DuressSetupPhase.failed);
      expect(states.last.hasError, isTrue);
      expect(await service.isRegistered(), isFalse);
    });

    test('duplicate registration → generic failed', () async {
      await bloc.register(realPin: '123456', duressPin: '654321');
      final states = <DuressSetupState>[];
      bloc.state.listen(states.add);

      await bloc.register(realPin: '999999', duressPin: '888888');

      expect(states.last.phase, DuressSetupPhase.failed);
      expect(states.last.hasError, isTrue);
    });

    test('empty PINs → generic failed (ArgumentError mapped)', () async {
      final states = <DuressSetupState>[];
      bloc.state.listen(states.add);

      await bloc.register(realPin: '', duressPin: '654321');

      expect(states.last.phase, DuressSetupPhase.failed);
      expect(states.last.hasError, isTrue);
    });
  });
}

/// Minimal in-memory [DuressService] fake for the setup state machine.
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
