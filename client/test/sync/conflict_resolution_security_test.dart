import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 5.5): conflict resolution operates strictly on
/// blind hashes, UUIDs, and timestamps — never on payload contents. The
/// resolver must never open/decrypt queue payloads, and no conflict branch
/// may print or log sensitive data.
void main() {
  final domainFiles = _dartFilesUnder('lib/repository/domain');
  const resolverFile = 'lib/repository/domain/sync_conflict_resolver.dart';
  const uiFile = 'lib/state/ui/conflict_resolution_banner.dart';

  group('SECURITY CHECKPOINT - conflict resolution leaks nothing (Task 5.5)',
      () {
    test('conflict_resolution.dart exists and defines the policy ports', () {
      final source = File('lib/repository/domain/conflict_resolution.dart')
          .readAsStringSync();
      expect(source, contains('abstract class ConflictResolutionPolicy'));
      expect(source, contains('class ServerAuthoritativeLastWriteWins'));
      expect(source, contains('class MergeAwareLastWriteWins'));
      expect(source, contains('abstract class MergePolicy'));
    });

    test('no payload-decryption or queue access in the domain file', () {
      final source = File('lib/repository/domain/conflict_resolution.dart')
          .readAsStringSync();
      for (final forbidden in [
        'QueuePayloadCipher',
        'open(',
        'decrypt',
        'payload',
        'sqflite',
        'hive_ce',
      ]) {
        expect(source.contains(forbidden), isFalse,
            reason:
                'conflict_resolution.dart must not reference "$forbidden" — '
                'it is a pure domain policy over versions, never payloads');
      }
    });

    test('resolver imports only the domain ports (no crypto/storage)', () {
      final source = File(resolverFile).readAsStringSync();
      expect(source, contains('SyncQueueItem'));
      expect(source, contains('SyncPushOutcome'));
      expect(source, contains('ConflictResolutionPolicy'));
      for (final forbidden in [
        'QueuePayloadCipher',
        'CryptoService',
        'sqflite',
        'hive_ce',
        'package:http',
        'dart:io',
      ]) {
        expect(source.contains(forbidden), isFalse,
            reason: '$resolverFile must not reference "$forbidden"');
      }
    });

    test('no prints / debugPrint anywhere in the conflict-resolution code', () {
      final files = [
        ...domainFiles,
        resolverFile,
        uiFile,
      ];
      for (final file in files) {
        if (!File(file).existsSync()) {
          continue;
        }
        final source = File(file).readAsStringSync();
        expect(source.contains('print('), isFalse,
            reason: '$file must not print');
        expect(source.contains('debugPrint('), isFalse,
            reason: '$file must not debugPrint');
      }
    });

    test('no raw PII-shaped literals in the resolver or domain code', () {
      for (final file in [resolverFile, ...domainFiles]) {
        final source = File(file).readAsStringSync();
        expect(source.contains('+91'), isFalse);
        expect(source.contains('hvs.'), isFalse);
        expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(source), isFalse);
        expect(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').hasMatch(source), isFalse);
      }
    });

    test('the UI banner is presentational: no data-layer or crypto imports',
        () {
      final source = File(uiFile).readAsStringSync();
      expect(source, contains('ConflictResolution'));
      for (final forbidden in [
        'SyncQueueRepository',
        'LocalDataStream',
        'QueuePayloadCipher',
        'CryptoService',
        'sqflite',
        'hive_ce',
        'http',
      ]) {
        expect(source.contains(forbidden), isFalse,
            reason: 'ConflictResolutionBanner must not reference "$forbidden"');
      }
    });

    test('banner renders only fixed labels, never dynamic ids', () {
      final source = File(uiFile).readAsStringSync();
      for (final label in [
        'Local edit kept',
        'Server version applied',
        'Changes merged',
      ]) {
        expect(source, contains(label));
      }
      // No interpolation of entity ids or hashes into the rendered strings.
      expect(source.contains('entityId'), isFalse);
      expect(source.contains('authorHash'), isFalse);
    });
  });
}

List<String> _dartFilesUnder(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) {
    return [];
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .toList();
}
