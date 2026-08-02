import 'dart:io';

import 'package:civic_commons/state/data/hive_non_sensitive_store.dart';
import 'package:civic_commons/state/data/memory_non_sensitive_store.dart';
import 'package:civic_commons/state/domain/non_sensitive_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

void main() {
  group('NonSensitiveGuard - defense-in-depth (Task 3.5)', () {
    test('rejects keys that reference sensitive data', () {
      expect(() => NonSensitiveGuard.assertNonSensitive('theme', 'dark'),
          returnsNormally);
      expect(
          () => NonSensitiveGuard.assertNonSensitive('cached_ciphertext', 'x'),
          throwsA(isA<SensitivePayloadException>()));
      expect(
          () => NonSensitiveGuard.assertNonSensitive('participant_hash', 'x'),
          throwsA(isA<SensitivePayloadException>()));
      expect(() => NonSensitiveGuard.assertNonSensitive('pin_store', 'x'),
          throwsA(isA<SensitivePayloadException>()));
      expect(() => NonSensitiveGuard.assertNonSensitive('vault_token', 'x'),
          throwsA(isA<SensitivePayloadException>()));
    });

    test('rejects values that look like encrypted blobs', () {
      // A long base64 blob — how ciphertext is encoded in this app.
      final base64Blob = List.filled(120, 'A').join() + '==';
      expect(() => NonSensitiveGuard.assertNonSensitive('theme', base64Blob),
          throwsA(isA<SensitivePayloadException>()));

      final hexBlob = List.filled(200, 'ab').join();
      expect(() => NonSensitiveGuard.assertNonSensitive('theme', hexBlob),
          throwsA(isA<SensitivePayloadException>()));

      expect(
          () => NonSensitiveGuard.assertNonSensitive(
              'theme', '-----BEGIN PRIVATE KEY-----'),
          throwsA(isA<SensitivePayloadException>()));
    });

    test('accepts ordinary non-sensitive values', () {
      expect(() => NonSensitiveGuard.assertNonSensitive('theme', 'dark'),
          returnsNormally);
      expect(() => NonSensitiveGuard.assertNonSensitive('academy_progress',
          '{"level":4,"xp":1200}'), returnsNormally);
      expect(() => NonSensitiveGuard.assertNonSensitive('karma_cache', '42'),
          returnsNormally);
    });
  });

  group('MemoryNonSensitiveStore (Task 3.5)', () {
    test('write/read/delete/clear round-trip', () async {
      final store = MemoryNonSensitiveStore();

      expect(await store.read('theme'), isNull);
      await store.write('theme', 'dark');
      expect(await store.read('theme'), 'dark');

      await store.write('locale', 'en');
      await store.delete('theme');
      expect(await store.read('theme'), isNull);
      expect(await store.read('locale'), 'en');

      await store.clear();
      expect(await store.read('locale'), isNull);
    });

    test('refuses sensitive payloads (guard enforced on write)', () async {
      final store = MemoryNonSensitiveStore();

      await expectLater(
        store.write('ciphertext_cache', 'AAAA'),
        throwsA(isA<SensitivePayloadException>()),
      );
      expect(await store.read('ciphertext_cache'), isNull);
    });
  });

  group('HiveNonSensitiveStore - real persistence (Task 3.5)', () {
    late Directory tempDir;
    late Box<String> box;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('civic_hive_test_');
      Hive.init(tempDir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      box = await Hive.openBox<String>('non_sensitive_test');
      await box.clear();
    });

    tearDown(() async {
      await box.close();
    });

    test('write/read/delete/clear round-trip through Hive', () async {
      final store = HiveNonSensitiveStore(box);

      expect(await store.read('ui_theme'), isNull);
      await store.write('ui_theme', 'dark');
      expect(await store.read('ui_theme'), 'dark');

      await store.write('academy_xp', '1200');
      await store.delete('ui_theme');
      expect(await store.read('ui_theme'), isNull);
      expect(await store.read('academy_xp'), '1200');

      await store.clear();
      expect(await store.read('academy_xp'), isNull);
    });

    test('values persist across box reopen (true disk persistence)',
        () async {
      final store = HiveNonSensitiveStore(box);
      await store.write('ui_theme', 'system');

      // Simulate an app restart: close and reopen the box.
      await box.close();
      final reopened = await Hive.openBox<String>('non_sensitive_test');
      final restored = HiveNonSensitiveStore(reopened);

      expect(await restored.read('ui_theme'), 'system');
      await reopened.close();
    });

    test('refuses sensitive payloads (guard enforced on write)', () async {
      final store = HiveNonSensitiveStore(box);

      await expectLater(
        store.write('blind_hash_cache', 'deadbeef'),
        throwsA(isA<SensitivePayloadException>()),
      );
      expect(await store.read('blind_hash_cache'), isNull);
    });
  });
}
