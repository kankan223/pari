import 'dart:typed_data';

import 'package:civic_commons/duress/data/duress_service_impl.dart';
import 'package:civic_commons/duress/domain/duress_service.dart';
import 'package:civic_commons/duress/domain/vault_database.dart';
import 'package:civic_commons/state/data/local_vault_unlock_bloc.dart';
import 'package:civic_commons/state/domain/vault_unlock_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 6.6): [LocalVaultUnlockBloc] routes the real PIN to the
/// real vault and the duress PIN to the decoy vault (database switching),
/// with IDENTICAL state transitions for both — only the returned result
/// differs. Wrong/empty PINs produce the same generic failure with no side
/// channel.
void main() {
  group('VaultUnlockBloc - registration state', () {
    test('start emits locked with isRegistered=false when unregistered',
        () async {
      final bloc = LocalVaultUnlockBloc(service: _FakeDuressService());
      final states = <VaultUnlockState>[];
      bloc.state.listen(states.add);
      await bloc.start();
      expect(states, hasLength(1));
      expect(states.single.phase, VaultUnlockPhase.locked);
      expect(states.single.isRegistered, isFalse);
      await bloc.close();
    });

    test('start emits locked with isRegistered=true when registered', () async {
      final service = _FakeDuressService();
      await service.registerPins(realPin: '123456', duressPin: '654321');
      final bloc = LocalVaultUnlockBloc(service: service);
      final states = <VaultUnlockState>[];
      bloc.state.listen(states.add);
      await bloc.start();
      expect(states.single.phase, VaultUnlockPhase.locked);
      expect(states.single.isRegistered, isTrue);
      await bloc.close();
    });
  });

  group('VaultUnlockBloc - database switching (real vs duress)', () {
    late _FakeDuressService service;
    late LocalVaultUnlockBloc bloc;

    setUp(() async {
      service = _FakeDuressService();
      await service.registerPins(realPin: '123456', duressPin: '654321');
      bloc = LocalVaultUnlockBloc(service: service);
    });

    tearDown(() => bloc.close());

    test('real PIN opens the REAL vault and emits unlocking → unlocked',
        () async {
      final states = <VaultUnlockState>[];
      bloc.state.listen(states.add);
      await bloc.start();

      final result = await bloc.unlock('123456');

      expect(result, isNotNull);
      expect(result!.kind, VaultKind.real);
      expect(result.database.name, DuressServiceImpl.realVaultName);
      // Transitions: locked → unlocking → unlocked (no error).
      expect(states.map((s) => s.phase), [
        VaultUnlockPhase.locked,
        VaultUnlockPhase.unlocking,
        VaultUnlockPhase.unlocked
      ]);
      expect(states.any((s) => s.hasError), isFalse);
    });

    test('duress PIN opens the DECOY vault with identical state transitions',
        () async {
      final states = <VaultUnlockState>[];
      bloc.state.listen(states.add);
      await bloc.start();

      final result = await bloc.unlock('654321');

      expect(result, isNotNull);
      expect(result!.kind, VaultKind.decoy);
      expect(result.database.name, DuressServiceImpl.decoyVaultName);
      // IDENTICAL transitions to the real-PIN case — the state stream never
      // reveals which vault was opened.
      expect(states.map((s) => s.phase), [
        VaultUnlockPhase.locked,
        VaultUnlockPhase.unlocking,
        VaultUnlockPhase.unlocked
      ]);
      expect(states.any((s) => s.hasError), isFalse);
    });

    test(
        'the real result reads the real vault; the decoy result reads the decoy vault',
        () async {
      // Write a record into the real vault through the real result.
      final realResult = await bloc.unlock('123456');
      await realResult!.database.writeRecord(
        realResult.key,
        VaultRecord(id: 'secret_note', payload: Uint8List.fromList([1, 2, 3])),
      );

      // The decoy result is a DIFFERENT database — it cannot see the record.
      final decoyResult = await bloc.unlock('654321');
      final decoyRecords =
          await decoyResult!.database.readRecords(decoyResult.key);
      expect(decoyRecords.map((r) => r.id), isNot(contains('secret_note')));

      // And the real vault still holds it.
      final realRecords = await realResult.database.readRecords(realResult.key);
      expect(realRecords.map((r) => r.id), contains('secret_note'));
    });
  });

  group('VaultUnlockBloc - generic failure (no side channel)', () {
    late _FakeDuressService service;
    late LocalVaultUnlockBloc bloc;

    setUp(() async {
      service = _FakeDuressService();
      await service.registerPins(realPin: '123456', duressPin: '654321');
      bloc = LocalVaultUnlockBloc(service: service);
    });

    tearDown(() => bloc.close());

    Future<VaultUnlockState> lastStateAfter(String pin) async {
      final states = <VaultUnlockState>[];
      bloc.state.listen(states.add);
      await bloc.start();
      await bloc.unlock(pin);
      return states.last;
    }

    test('wrong PIN returns null and emits failed with hasError', () async {
      final state = await lastStateAfter('000000');
      expect(state.phase, VaultUnlockPhase.failed);
      expect(state.hasError, isTrue);
    });

    test(
        'a PIN one digit off the real PIN fails identically to one off the duress PIN',
        () async {
      final nearReal = await lastStateAfter('123457');
      final nearDuress = await lastStateAfter('654322');
      // Same phase, same generic error flag — no way to tell which vault the
      // PIN was "close to".
      expect(nearReal.phase, nearDuress.phase);
      expect(nearReal.hasError, nearDuress.hasError);
      expect(nearReal.hasError, isTrue);
    });

    test('empty PIN fails with the same generic presentation', () async {
      final state = await lastStateAfter('');
      expect(state.phase, VaultUnlockPhase.failed);
      expect(state.hasError, isTrue);
    });

    test('unlock with a failing service returns null without throwing',
        () async {
      final failing = _FailingDuressService();
      await failing.registerPins(realPin: '123456', duressPin: '654321');
      final failingBloc = LocalVaultUnlockBloc(service: failing);
      final states = <VaultUnlockState>[];
      failingBloc.state.listen(states.add);
      await failingBloc.start();

      final result = await failingBloc.unlock('123456');
      expect(result, isNull);
      expect(states.last.phase, VaultUnlockPhase.failed);
      expect(states.last.hasError, isTrue);
      await failingBloc.close();
    });
  });
}

/// In-memory [DuressService] fake: two named vault databases, PIN-mapped
/// (real vs duress) — mirrors the real service's decryption-based selection
/// for the purposes of state-machine testing.
class _FakeDuressService implements DuressService {
  final _FakeVaultDatabase realVault =
      _FakeVaultDatabase(name: DuressServiceImpl.realVaultName);
  final _FakeVaultDatabase decoyVault =
      _FakeVaultDatabase(name: DuressServiceImpl.decoyVaultName);
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
    if (pin.isEmpty) {
      throw ArgumentError('PIN cannot be empty');
    }
    if (pin == realPin) {
      return UnlockResult(
        kind: VaultKind.real,
        database: realVault,
        key: Uint8List(32),
      );
    }
    if (pin == duressPin) {
      return UnlockResult(
        kind: VaultKind.decoy,
        database: decoyVault,
        key: Uint8List(32),
      );
    }
    throw const DuressPinException('PIN could not unlock any vault');
  }
}

/// [DuressService] that fails at unlock with an unexpected error (the bloc
/// must never crash — generic failure instead).
class _FailingDuressService extends _FakeDuressService {
  @override
  Future<UnlockResult> unlock(String pin) async {
    throw StateError('unexpected storage failure');
  }
}

class _FakeVaultDatabase implements VaultDatabase {
  @override
  final String name;
  final Map<String, VaultRecord> _records = {};

  _FakeVaultDatabase({required this.name});

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteAll() async {
    _records.clear();
  }

  @override
  Future<void> initialize({
    required Uint8List key,
    required Uint8List salt,
    List<VaultRecord> seedRecords = const [],
  }) async {
    for (final record in seedRecords) {
      _records[record.id] = record;
    }
  }

  @override
  Future<bool> isInitialized() async => true;

  @override
  Future<Uint8List> readSalt() async => Uint8List(16);

  @override
  Future<List<VaultRecord>> readRecords(Uint8List key) async =>
      _records.values.toList();

  @override
  Future<bool> tryOpen(Uint8List key) async => true;

  @override
  Future<void> writeRecord(Uint8List key, VaultRecord record) async {
    _records[record.id] = record;
  }
}
