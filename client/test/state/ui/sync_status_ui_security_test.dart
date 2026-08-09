import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 5.4): the sync-status UI is a pure
/// presentation layer — it consumes the [SyncStatusBloc] state stream only,
/// renders fixed enum labels + a non-sensitive count, and never touches the
/// database, network, or queue repository. No PII may appear in status
/// strings, tooltips, or widget trees.
void main() {
  final uiFiles = _dartFilesUnder('lib/state/ui');

  group('SECURITY CHECKPOINT - sync status UI leaks nothing (Task 5.4)', () {
    test('lib/state/ui exists and contains the status bar', () {
      expect(uiFiles, isNotEmpty,
          reason: 'lib/state/ui must contain the SyncStatusBar source');
      expect(
        uiFiles.any((p) => p.endsWith('sync_status_bar.dart')),
        isTrue,
      );
    });

    test('no direct data-layer access from the status bar', () {
      final bar = uiFiles.firstWhere((p) => p.endsWith('sync_status_bar.dart'));
      final source = File(bar).readAsStringSync();

      // The widget must consume ONLY the BLoC interface stream.
      expect(source, contains('SyncStatusBloc'));
      // No repository / database / network / crypto imports.
      for (final forbidden in [
        'SyncQueueRepository',
        'LocalSyncStatusBloc',
        'LocalDataStream',
        'sqflite',
        'hive_ce',
        'secure_storage',
        'http',
        'NetworkInfoProvider',
        'QueuePayloadCipher',
      ]) {
        expect(source.contains(forbidden), isFalse,
            reason: 'SyncStatusBar must not reference "$forbidden" — UI '
                'consumes only the SyncStatusBloc stream');
      }
    });

    test('no prints / debugPrint in the status bar', () {
      for (final file in uiFiles) {
        final source = File(file).readAsStringSync();
        expect(source.contains('print('), isFalse,
            reason: '$file must not print');
        expect(source.contains('debugPrint('), isFalse,
            reason: '$file must not debugPrint');
      }
    });

    test('no raw PII-shaped literals in the status bar source', () {
      final bar = uiFiles.firstWhere((p) => p.endsWith('sync_status_bar.dart'));
      final source = File(bar).readAsStringSync();

      // No hardcoded phone numbers, emails, token prefixes, or 64-hex hashes.
      expect(source.contains('+91'), isFalse);
      expect(source.contains('hvs.'), isFalse);
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(source), isFalse);
      expect(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').hasMatch(source), isFalse);
    });

    test('status labels are exactly the fixed enum names', () {
      final bar = uiFiles.firstWhere((p) => p.endsWith('sync_status_bar.dart'));
      final source = File(bar).readAsStringSync();

      for (final label in ['LIVE', 'CACHED', 'QUEUED', 'OFFLINE']) {
        expect(source, contains("'$label'"));
      }
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
