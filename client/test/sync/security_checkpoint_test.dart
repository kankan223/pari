import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 3.4): background sync respects the offline-first
/// architecture — the sync layer performs no direct HTTP calls, depends on
/// the repository layer's injected SyncSink as the only outbound path, and
/// never logs raw payloads.
void main() {
  final syncFiles = _dartFilesUnder('lib/sync');

  group('SECURITY CHECKPOINT - background sync is offline-first', () {
    test('no HTTP/network transport imports anywhere in lib/sync', () {
      const forbidden = [
        'package:http/',
        'package:dio/',
        'dart:io', // no raw sockets / HttpClient
        'package:web_socket_channel',
        'package:socket_io',
        'HttpClient',
        'WebSocket',
        'InternetAddress',
      ];

      expect(syncFiles, isNotEmpty,
          reason: 'lib/sync must contain source files');

      for (final file in syncFiles) {
        final source = File(file).readAsStringSync();
        for (final f in forbidden) {
          expect(
            source.contains(f),
            isFalse,
            reason: '$file must not reference "$f" — background sync goes '
                'through the repository layer SyncSink, never raw transport',
          );
        }
      }
    });

    test('the worker depends on the local queue + injected sink only', () {
      final workerFile = syncFiles
          .firstWhere((p) => p.endsWith('background_sync_worker.dart'));
      final source = File(workerFile).readAsStringSync();

      expect(source, contains('SyncQueueRepository'));
      expect(source, contains('SyncSink'));
      // No network-capable dependencies beyond the injected sink.
      expect(source.contains('package:http'), isFalse);
      expect(source.contains('dart:io'), isFalse);
    });

    test('the trigger fires sync only on reconnection (online)', () {
      final triggerFile = syncFiles
          .firstWhere((p) => p.endsWith('reconnection_sync_trigger.dart'));
      final source = File(triggerFile).readAsStringSync();

      // The trigger gates on status == online before running the worker.
      expect(source, contains('NetworkStatus.online'));
      expect(source, contains('runOnce'));
    });

    test('no plaintext payloads are ever printed or logged', () {
      for (final file in syncFiles) {
        final source = File(file).readAsStringSync();
        expect(source.contains('print('), isFalse,
            reason: '$file must not print payload data');
        expect(source.contains('debugPrint('), isFalse,
            reason: '$file must not debugPrint payload data');
      }
    });

    test('network state is used for sync gating only, never persisted', () {
      for (final file in syncFiles) {
        final source = File(file).readAsStringSync();
        // No persistence of network state anywhere in the layer.
        expect(source.contains('sqflite'), isFalse,
            reason: '$file must not persist network state');
        expect(source.contains('secure_storage'), isFalse,
            reason: '$file must not persist network state');
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
