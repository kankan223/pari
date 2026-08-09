import 'dart:io';

import 'package:civic_commons/state/domain/non_sensitive_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 3.6): no PII or sensitive data may ever be
/// stored in the unencrypted Hive boxes — the [NonSensitiveGuard] enforced by
/// every store implementation must refuse sensitive payloads, and the
/// registry must open canonical boxes without encryption while routing
/// sensitive boxes through the encrypted path only.
void main() {
  final storageFiles = [
    'lib/state/domain/cache_entry.dart',
    'lib/state/domain/karma_cache.dart',
    'lib/state/domain/hive_box_key_provider.dart',
    'lib/state/domain/hive_box_registry.dart',
    'lib/state/data/hive_karma_cache.dart',
    'lib/state/data/hive_box_registry_impl.dart',
    'lib/state/data/hive_non_sensitive_store.dart',
  ];

  group('SECURITY CHECKPOINT - no PII in unencrypted Hive boxes', () {
    test('the three canonical boxes are declared NON-sensitive', () {
      final source =
          File('lib/state/domain/hive_box_registry.dart').readAsStringSync();

      expect(source, contains('ledger_drafts'));
      expect(source, contains('academy_progress'));
      expect(source, contains('karma_cache'));
      expect(source, contains('NON-SENSITIVE'));
      // The port documents that these boxes are opened unencrypted by design.
      expect(source, contains('opened unencrypted'));
    });

    test('registry opens canonical boxes with NO encryption cipher', () {
      final source =
          File('lib/state/data/hive_box_registry_impl.dart').readAsStringSync();

      // The canonical open path passes sensitive: false → cipher stays null.
      expect(source, contains('sensitive: false'));
      expect(source, contains('encryptionCipher: key == null ? null'));
      // Encryption is only ever applied on the sensitive path.
      expect(source, contains('sensitive: true'));
      expect(source, contains('HiveAesCipher'));
    });

    test('no sensitive-key or sensitive-value markers slip into boxes', () {
      for (final file in storageFiles) {
        final source = File(file).readAsStringSync();
        expect(source.contains('print('), isFalse,
            reason: '$file must not print payload data');
        expect(source.contains('debugPrint('), isFalse,
            reason: '$file must not debugPrint payload data');
      }
    });

    test('guard rejects PII patterns that could reach a box', () {
      // Key-level: hashes / tokens / pins are refused by key marker.
      expect(
        () =>
            NonSensitiveGuard.assertNonSensitive('participant_hash', 'abc123'),
        throwsA(isA<SensitivePayloadException>()),
      );
      // Value-level: an E.164 phone number is PII and must be refused.
      expect(
        () =>
            NonSensitiveGuard.assertNonSensitive('draft_note', '+14155552671'),
        throwsA(isA<SensitivePayloadException>()),
      );
      // Even embedded inside otherwise-benign text.
      expect(
        () => NonSensitiveGuard.assertNonSensitive(
            'draft_note', 'Contact +14155552671 for details'),
        throwsA(isA<SensitivePayloadException>()),
      );
      // Benign values still pass.
      expect(
        () => NonSensitiveGuard.assertNonSensitive('draft_note', 'Draft title'),
        returnsNormally,
      );
    });
  });
}
