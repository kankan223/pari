import 'dart:io';

import 'package:civic_commons/state/data/hive_box_registry_impl.dart';
import 'package:civic_commons/state/domain/hive_box_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'storage_fakes.dart';

void main() {
  group('HiveBoxRegistry - CRUD on canonical boxes (Task 3.6)', () {
    late Directory tempDir;
    late FakeHiveBoxKeyProvider keyProvider;
    late HiveBoxRegistryImpl registry;

    void _deleteBoxFiles() {
      for (final name in [
        HiveBoxNames.ledgerDrafts,
        HiveBoxNames.academyProgress,
        HiveBoxNames.karmaCache,
        'sensitive_notes',
      ]) {
        final file = File('${tempDir.path}/$name.hive');
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    }

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('civic_hive_registry_');
    });

    tearDownAll(() async {
      await Hive.close();
      tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      // Clean slate: drop any box files left by a previous test.
      _deleteBoxFiles();
      keyProvider = FakeHiveBoxKeyProvider();
      registry = HiveBoxRegistryImpl(
        hive: Hive,
        path: tempDir.path,
        keyProvider: keyProvider,
      );
      await registry.initialize();
    });

    tearDown(() async {
      await registry.close();
      _deleteBoxFiles();
    });

    test('initialize() opens all three canonical boxes', () {
      expect(registry.isInitialized, isTrue);
      expect(registry.ledgerDrafts, isNotNull);
      expect(registry.academyProgress, isNotNull);
      expect(registry.karmaCache, isNotNull);
    });

    test('initialize() is idempotent', () async {
      await registry.initialize();
      expect(registry.isInitialized, isTrue);
    });

    test('ledger_drafts box: write/read/delete/clear round-trip', () async {
      final box = registry.ledgerDrafts;

      expect(await box.read('draft_1'), isNull);
      await box.write('draft_1', '{"title":"My draft","body_ref":"enc"}');
      expect(await box.read('draft_1'), contains('My draft'));

      await box.write('draft_2', '{"title":"Second"}');
      await box.delete('draft_1');
      expect(await box.read('draft_1'), isNull);
      expect(await box.read('draft_2'), isNotNull);

      await box.clear();
      expect(await box.read('draft_2'), isNull);
    });

    test('academy_progress box: write/read/delete/clear round-trip',
        () async {
      final box = registry.academyProgress;

      await box.write('level', '4');
      await box.write('xp', '1200');
      expect(await box.read('level'), '4');
      expect(await box.read('xp'), '1200');

      await box.delete('level');
      expect(await box.read('level'), isNull);
      expect(await box.read('xp'), '1200');

      await box.clear();
      expect(await box.read('xp'), isNull);
    });

    test('karma_cache box: karma write/read/invalidate round-trip', () async {
      final karma = registry.karmaCache;

      expect(await karma.readKarma('peer_1'), isNull);
      await karma.writeKarma('peer_1', '42');
      expect(await karma.readKarma('peer_1'), '42');
      expect(await karma.isFresh('peer_1'), isTrue);

      await karma.invalidate('peer_1');
      expect(await karma.readKarma('peer_1'), isNull);

      await karma.writeKarma('peer_1', '42');
      await karma.invalidateAll();
      expect(await karma.readKarma('peer_1'), isNull);
    });

    test('canonical boxes persist across registry reopen', () async {
      await registry.ledgerDrafts.write('draft_1', '{"title":"persist"}');
      await registry.academyProgress.write('level', '7');
      await registry.karmaCache.writeKarma('peer_1', '42');
      await registry.close();

      final reopened = HiveBoxRegistryImpl(
        hive: Hive,
        path: tempDir.path,
        keyProvider: keyProvider,
      );
      await reopened.initialize();

      expect(await reopened.ledgerDrafts.read('draft_1'), contains('persist'));
      expect(await reopened.academyProgress.read('level'), '7');
      expect(await reopened.karmaCache.readKarma('peer_1'), '42');
      await reopened.close();
    });

    test('accessors throw StateError before initialize()', () async {
      await registry.close();
      final fresh = HiveBoxRegistryImpl(
        hive: Hive,
        path: tempDir.path,
        keyProvider: keyProvider,
      );

      expect(() => fresh.ledgerDrafts, throwsStateError);
      expect(() => fresh.academyProgress, throwsStateError);
      expect(() => fresh.karmaCache, throwsStateError);
    });
  });

  group('HiveBoxRegistry - sensitive boxes are encrypted at rest (Task 3.6)',
      () {
    late Directory tempDir;
    late FakeHiveBoxKeyProvider keyProvider;
    late HiveBoxRegistryImpl registry;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('civic_hive_sensitive_');
    });

    tearDownAll(() async {
      await Hive.close();
      tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      // Hermetic state per test: close any stray boxes from a previous run,
      // drop leftover files, then re-init through the registry.
      await Hive.close();
      for (final name in ['sensitive_notes', 'alt_box']) {
        final file = File('${tempDir.path}/$name.hive');
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
      keyProvider = FakeHiveBoxKeyProvider();
      registry = HiveBoxRegistryImpl(
        hive: Hive,
        path: tempDir.path,
        keyProvider: keyProvider,
      );
      await registry.initialize();
    });

    tearDown(() async {
      await registry.close();
    });

    test('sensitive box requires a registered key (StateError otherwise)',
        () async {
      // No key registered for 'sensitive_notes' → must refuse to open.
      await expectLater(
        registry.openSensitiveBox('sensitive_notes'),
        throwsA(isA<StateError>()),
      );
    });

    test('sensitive box encrypts values at rest (plaintext never on disk)',
        () async {
      keyProvider.register('sensitive_notes');
      final box = await registry.openSensitiveBox('sensitive_notes');

      const secret = 'TOP-SECRET-PLAINTEXT-123';
      await box.write('note', secret);
      expect(await box.read('note'), secret);
      await registry.close();

      // The raw .hive file must NOT contain the plaintext bytes.
      final raw =
          File('${tempDir.path}/sensitive_notes.hive').readAsBytesSync();
      final asString = String.fromCharCodes(raw);
      expect(asString.contains(secret), isFalse,
          reason: 'encrypted box must not leak plaintext to disk');
    });

    test('wrong encryption key never reveals the plaintext', () async {
      keyProvider.register('sensitive_notes', fill: 7);
      final box = await registry.openSensitiveBox('sensitive_notes');
      await box.write('note', 'SECRET-1');
      await registry.close();

      // Reopen with a DIFFERENT key. hive_ce may refuse the open outright
      // (HiveError) or crash-recover to an empty box — either way it must
      // NEVER decrypt and return the original plaintext.
      final attacker = HiveBoxRegistryImpl(
        hive: Hive,
        path: tempDir.path,
        keyProvider: keyProvider..register('sensitive_notes', fill: 9),
      );
      await attacker.initialize();

      String? leaked;
      try {
        final box2 = await attacker.openSensitiveBox('sensitive_notes');
        leaked = await box2.read('note');
      } on HiveError {
        leaked = null; // refused outright — equally secure
      }

      expect(leaked, isNot('SECRET-1'));
      await attacker.close();
    });

    test('same key reopens the sensitive box and reads the value back',
        () async {
      keyProvider.register('sensitive_notes', fill: 7);
      final box = await registry.openSensitiveBox('sensitive_notes');
      await box.write('note', 'SECRET-1');
      await registry.close();

      final reopened = HiveBoxRegistryImpl(
        hive: Hive,
        path: tempDir.path,
        keyProvider: keyProvider,
      );
      await reopened.initialize();
      final box2 = await reopened.openSensitiveBox('sensitive_notes');
      expect(await box2.read('note'), 'SECRET-1');
      await reopened.close();
    });
  });
}
