import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/duress/data/duress_service_impl.dart';
import 'package:civic_commons/duress/data/file_vault_database.dart';
import 'package:civic_commons/duress/domain/duress_service.dart';
import 'package:civic_commons/duress/domain/vault_database.dart';
import 'package:civic_commons/state/data/local_duress_setup_bloc.dart';
import 'package:civic_commons/state/data/local_vault_unlock_bloc.dart';
import 'package:civic_commons/state/domain/duress_setup_state.dart';
import 'package:civic_commons/state/domain/vault_unlock_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 6.6, integration with the REAL duress service + real vault
/// files): the full onboarding → unlock lifecycle. The real PIN opens the
/// real vault (records persist there); the duress PIN opens the DECOY vault
/// (cannot see the real records); and the persisted files contain NO
/// indicator of which PIN is real vs duress.
void main() {
  late Directory tempDir;
  late DuressServiceImpl service;
  late LocalDuressSetupBloc setupBloc;
  late LocalVaultUnlockBloc unlockBloc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('duress_integration_');
    final crypto = CryptoServiceImpl();
    service = DuressServiceImpl(
      cryptoService: crypto,
      realVault: FileVaultDatabase(
        name: DuressServiceImpl.realVaultName,
        file: File('${tempDir.path}/${DuressServiceImpl.realVaultName}'),
        cryptoService: crypto,
      ),
      decoyVault: FileVaultDatabase(
        name: DuressServiceImpl.decoyVaultName,
        file: File('${tempDir.path}/${DuressServiceImpl.decoyVaultName}'),
        cryptoService: crypto,
      ),
    );
    setupBloc = LocalDuressSetupBloc(service: service);
    unlockBloc = LocalVaultUnlockBloc(service: service);
  });

  tearDown(() async {
    await setupBloc.close();
    await unlockBloc.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('onboarding: registering via the setup bloc initializes both vaults',
      () async {
    final states = <DuressSetupState>[];
    setupBloc.state.listen(states.add);
    await setupBloc.start();

    await setupBloc.register(realPin: '123456', duressPin: '654321');

    expect(states.last.phase, DuressSetupPhase.registered);
    expect(await service.isRegistered(), isTrue);
    // Both vault files exist on disk.
    final names = tempDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(
      names,
      equals(
          {DuressServiceImpl.realVaultName, DuressServiceImpl.decoyVaultName}),
    );
  });

  test('real PIN unlocks the real vault; records written there persist',
      () async {
    await setupBloc.register(realPin: '123456', duressPin: '654321');

    final result = await unlockBloc.unlock('123456');

    expect(result!.kind, VaultKind.real);
    await result.database.writeRecord(
      result.key,
      VaultRecord(id: 'secret_note', payload: _utf8('real data')),
    );
    final records = await result.database.readRecords(result.key);
    final note = records.firstWhere((r) => r.id == 'secret_note');
    expect(utf8.decode(note.payload), 'real data');
  });

  test('duress PIN unlocks the DECOY vault — real records are invisible',
      () async {
    await setupBloc.register(realPin: '123456', duressPin: '654321');

    // Write a real record first.
    final real = await unlockBloc.unlock('123456');
    await real!.database.writeRecord(
      real.key,
      VaultRecord(id: 'secret_note', payload: _utf8('real data')),
    );

    // The duress PIN opens the decoy vault — a DIFFERENT database.
    final decoy = await unlockBloc.unlock('654321');
    expect(decoy!.kind, VaultKind.decoy);
    final decoyRecords = await decoy.database.readRecords(decoy.key);
    expect(decoyRecords.map((r) => r.id), isNot(contains('secret_note')));
  });

  test('wrong PIN fails generically through the real service', () async {
    await setupBloc.register(realPin: '123456', duressPin: '654321');
    final states = <VaultUnlockState>[];
    unlockBloc.state.listen(states.add);

    final result = await unlockBloc.unlock('000000');

    expect(result, isNull);
    expect(states.last.phase, VaultUnlockPhase.failed);
    expect(states.last.hasError, isTrue);
  });

  test('SECURITY: persisted vault files contain no real/duress indicator',
      () async {
    await setupBloc.register(realPin: '123456', duressPin: '654321');

    // Read every byte registration wrote to disk.
    final files = tempDir.listSync().whereType<File>().toList();
    final rawBytes = <int>[];
    for (final file in files) {
      rawBytes.addAll(await file.readAsBytes());
    }
    final rawString = String.fromCharCodes(rawBytes);

    // No indicator terms anywhere in persisted bytes — the app never stores
    // which PIN is real vs duress.
    const forbidden = [
      'real',
      'duress',
      'decoy',
      'is_real',
      'is_duress',
      'true',
      'false',
    ];
    for (final term in forbidden) {
      expect(
        rawString.toLowerCase().contains(term),
        isFalse,
        reason: 'Persisted data must never contain "$term"',
      );
    }
  });
}

Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));
