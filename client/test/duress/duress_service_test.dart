import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/crypto/crypto_service.dart';
import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/duress/data/duress_service_impl.dart';
import 'package:civic_commons/duress/data/file_vault_database.dart';
import 'package:civic_commons/duress/domain/duress_service.dart';
import 'package:civic_commons/duress/domain/vault_database.dart';

void main() {
  late Directory tempDir;
  late CryptoService cryptoService;

  /// Builds a fully wired DuressServiceImpl backed by real files.
  DuressServiceImpl buildService() {
    final realVault = FileVaultDatabase(
      name: DuressServiceImpl.realVaultName,
      file: File('${tempDir.path}/${DuressServiceImpl.realVaultName}'),
      cryptoService: cryptoService,
    );
    final decoyVault = FileVaultDatabase(
      name: DuressServiceImpl.decoyVaultName,
      file: File('${tempDir.path}/${DuressServiceImpl.decoyVaultName}'),
      cryptoService: cryptoService,
    );
    return DuressServiceImpl(
      cryptoService: cryptoService,
      realVault: realVault,
      decoyVault: decoyVault,
    );
  }

  setUp(() async {
    cryptoService = CryptoServiceImpl();
    tempDir = await Directory.systemTemp.createTemp('duress_test_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('DuressService - Dual PIN Registration', () {
    test('should register real and duress PINs and initialize both databases',
        () async {
      // Arrange
      final service = buildService();

      // Act
      await service.registerPins(realPin: '123456', duressPin: '654321');

      // Assert
      expect(await service.isRegistered(), isTrue);
      final files = tempDir.listSync().whereType<File>().toList();
      expect(files.length, equals(2));
      final names = files.map((f) => f.uri.pathSegments.last).toSet();
      expect(
        names,
        equals({DuressServiceImpl.realVaultName, DuressServiceImpl.decoyVaultName}),
      );
    });

    test('should reject empty PINs', () async {
      // Arrange
      final service = buildService();

      // Act & Assert
      await expectLater(
        service.registerPins(realPin: '', duressPin: '654321'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should reject identical real and duress PINs', () async {
      // Arrange
      final service = buildService();

      // Act & Assert
      await expectLater(
        service.registerPins(realPin: '123456', duressPin: '123456'),
        throwsA(isA<DuressRegistrationException>()),
      );
    });

    test('should reject duplicate registration', () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');

      // Act & Assert
      await expectLater(
        service.registerPins(realPin: '111111', duressPin: '222222'),
        throwsA(isA<DuressRegistrationException>()),
      );
    });
  });

  group('DuressService - Database Key Derivation Paths', () {
    test('each PIN has an independent Argon2id derivation path (different salts)',
        () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');

      // Act
      final realVault = FileVaultDatabase(
        name: DuressServiceImpl.realVaultName,
        file: File('${tempDir.path}/${DuressServiceImpl.realVaultName}'),
        cryptoService: cryptoService,
      );
      final decoyVault = FileVaultDatabase(
        name: DuressServiceImpl.decoyVaultName,
        file: File('${tempDir.path}/${DuressServiceImpl.decoyVaultName}'),
        cryptoService: cryptoService,
      );
      final realSalt = await realVault.readSalt();
      final decoySalt = await decoyVault.readSalt();

      // Assert: salts are distinct → derivation paths are distinct
      expect(realSalt, isNot(equals(decoySalt)));

      // Keys derived from each PIN with its own salt must differ.
      final realKey = await cryptoService.deriveKeyFromPin('123456', realSalt);
      final duressKey = await cryptoService.deriveKeyFromPin('654321', decoySalt);
      expect(realKey, isNot(equals(duressKey)));
    });
  });

  group('DuressService - Real PIN unlocks real vault', () {
    test('real PIN opens the real vault (VaultKind.real)', () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');

      // Act
      final result = await service.unlock('123456');

      // Assert
      expect(result.kind, equals(VaultKind.real));
      expect(result.database.name, equals(DuressServiceImpl.realVaultName));
      expect(result.key.length, equals(32));
    });

    test('real PIN can read/write records in the real vault', () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');
      final result = await service.unlock('123456');

      // Act
      await result.database.writeRecord(
        result.key,
        VaultRecord(id: 'secret_note', payload: _utf8('real data')),
      );
      final records = await result.database.readRecords(result.key);

      // Assert
      final note = records.firstWhere((r) => r.id == 'secret_note');
      expect(utf8.decode(note.payload), equals('real data'));
    });
  });

  group('DuressService - Duress PIN unlocks decoy vault', () {
    test('duress PIN opens the decoy vault (VaultKind.decoy)', () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');

      // Act
      final result = await service.unlock('654321');

      // Assert
      expect(result.kind, equals(VaultKind.decoy));
      expect(result.database.name, equals(DuressServiceImpl.decoyVaultName));
      expect(result.key.length, equals(32));
    });

    test('duress PIN cannot read real-vault records', () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');
      final realResult = await service.unlock('123456');
      await realResult.database.writeRecord(
        realResult.key,
        VaultRecord(id: 'secret_note', payload: _utf8('real data')),
      );

      // Act
      final decoyResult = await service.unlock('654321');

      // Assert: the decoy vault does not contain the real vault's records
      final decoyRecords = await decoyResult.database.readRecords(decoyResult.key);
      final ids = decoyRecords.map((r) => r.id).toList();
      expect(ids, isNot(contains('secret_note')));
    });

    test('decoy database is initialized with plausible content', () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');
      final result = await service.unlock('654321');

      // Act
      final records = await result.database.readRecords(result.key);

      // Assert: the decoy looks like a normal database, not an empty shell
      expect(records, isNotEmpty);
      final ids = records.map((r) => r.id).toList();
      expect(ids, contains('schema_version'));
    });
  });

  group('DuressService - Database selection by decryption only', () {
    test('cross-unlock fails: real PIN cannot open decoy, duress PIN cannot open real',
        () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');

      final realVault = FileVaultDatabase(
        name: DuressServiceImpl.realVaultName,
        file: File('${tempDir.path}/${DuressServiceImpl.realVaultName}'),
        cryptoService: cryptoService,
      );
      final decoyVault = FileVaultDatabase(
        name: DuressServiceImpl.decoyVaultName,
        file: File('${tempDir.path}/${DuressServiceImpl.decoyVaultName}'),
        cryptoService: cryptoService,
      );

      // Real PIN's key must NOT open the decoy database, and vice versa.
      final realSalt = await realVault.readSalt();
      final realKey = await cryptoService.deriveKeyFromPin('123456', realSalt);
      expect(await decoyVault.tryOpen(realKey), isFalse);

      final decoySalt = await decoyVault.readSalt();
      final duressKey = await cryptoService.deriveKeyFromPin('654321', decoySalt);
      expect(await realVault.tryOpen(duressKey), isFalse);
    });

    test('unlock with a wrong PIN throws DuressPinException for both vaults',
        () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');

      // Act & Assert: identical error regardless of which PIN is "closer"
      await expectLater(
        service.unlock('000000'),
        throwsA(isA<DuressPinException>()),
      );
      await expectLater(
        service.unlock('654322'), // one digit off the duress PIN
        throwsA(isA<DuressPinException>()),
      );
      await expectLater(
        service.unlock('123457'), // one digit off the real PIN
        throwsA(isA<DuressPinException>()),
      );
    });

    test('unlock with empty PIN throws ArgumentError', () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');

      // Act & Assert
      await expectLater(
        service.unlock(''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('DuressService - SECURITY CHECKPOINT', () {
    test(
        'no flag, boolean, or indicator of real vs duress is ever persisted '
        'to disk', () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');

      // Act: read every byte the registration flow wrote to disk
      final files = tempDir.listSync().whereType<File>().toList();
      final rawBytes = <int>[];
      for (final file in files) {
        rawBytes.addAll(await file.readAsBytes());
      }
      final rawString = String.fromCharCodes(rawBytes);

      // Assert: no indicator terms exist anywhere in persisted bytes
      final forbidden = [
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

    test('real and decoy database files are structurally indistinguishable',
        () async {
      // Arrange
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');

      // Act
      final realFile =
          File('${tempDir.path}/${DuressServiceImpl.realVaultName}');
      final decoyFile =
          File('${tempDir.path}/${DuressServiceImpl.decoyVaultName}');
      final realBytes = await realFile.readAsBytes();
      final decoyBytes = await decoyFile.readAsBytes();

      // Assert: identical size and header structure (magic + salt + length),
      // both fully encrypted, no plaintext metadata revealing which is which.
      expect(realBytes.length, greaterThan(28));
      expect(decoyBytes.length, greaterThan(28));
      expect(
        realBytes.length,
        equals(decoyBytes.length),
        reason: 'File size must not reveal which vault is the decoy',
      );
      expect(
        realBytes.sublist(0, 8),
        equals(decoyBytes.sublist(0, 8)),
        reason: 'Both files must start with the same magic header',
      );
      // Neither file contains any plaintext record ids or marker words.
      final realText = String.fromCharCodes(realBytes);
      final decoyText = String.fromCharCodes(decoyBytes);
      expect(realText.contains('schema_version'), isFalse);
      expect(decoyText.contains('schema_version'), isFalse);
    });

    test('keys are re-derived at unlock after registration', () async {
      // The service wipes derived keys post-registration; unlock re-derives.
      final service = buildService();
      await service.registerPins(realPin: '123456', duressPin: '654321');

      // Both PINs still unlock their respective vaults (keys re-derived).
      final realResult = await service.unlock('123456');
      final decoyResult = await service.unlock('654321');
      expect(realResult.kind, equals(VaultKind.real));
      expect(decoyResult.kind, equals(VaultKind.decoy));
    });
  });
}

Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));
