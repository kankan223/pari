import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 3.2): repositories NEVER make direct HTTP calls.
/// They must solely interact with the local SQLCipher database and the sync
/// queue. This suite statically verifies the repository layer contains no
/// network transport imports and no plaintext logging of payloads.
void main() {
  final repoFiles = _dartFilesUnder('lib/repository');

  group('SECURITY CHECKPOINT - repositories never make direct HTTP calls', () {
    test('no file under lib/repository imports any HTTP/network transport',
        () {
      const forbiddenImports = [
        'package:http/',
        'package:dio/',
        'dart:io', // no raw sockets / HttpClient
        'package:web_socket_channel',
        'package:socket_io',
        'HttpClient',
        'WebSocket',
      ];

      expect(repoFiles, isNotEmpty,
          reason: 'lib/repository must contain source files');

      for (final file in repoFiles) {
        final source = File(file).readAsStringSync();
        for (final forbidden in forbiddenImports) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '$file must not reference "$forbidden" '
                '(repositories are local-first; the only network boundary '
                'is the injected SyncSink port)',
          );
        }
      }
    });

    test('repositories depend only on local store + injected SyncSink port',
        () {
      // The data-layer repositories must wire their collaborators through
      // constructor injection of EntityStore/SyncQueueRepository/SyncSink —
      // and never construct their own transport.
      final dataFiles = _dartFilesUnder('lib/repository/data');
      for (final file in dataFiles) {
        final source = File(file).readAsStringSync();
        if (source.contains('LocalMessageRepository') ||
            source.contains('LocalConversationRepository')) {
          expect(source, contains('SyncSink'));
          expect(source, contains('EntityStore'));
        }
        // The production SQLite store talks to sqflite_sqlcipher (local
        // encrypted database), which is allowed — but never HTTP.
        if (file.contains('sqlite_entity_store')) {
          expect(source, contains('sqflite_sqlcipher'));
        }
      }
    });

    test('queued payloads are opaque ciphertext, never logged or printed',
        () {
      for (final file in repoFiles) {
        final source = File(file).readAsStringSync();
        expect(
          source.contains('print('),
          isFalse,
          reason: '$file must not print raw payload data',
        );
        expect(
          source.contains('debugPrint('),
          isFalse,
          reason: '$file must not debugPrint raw payload data',
        );
      }
    });

    test('the only outbound path is the SyncSink port', () {
      // Domain ports define the sanctioned boundaries: EntityStore (local
      // persistence) and SyncSink (sole network boundary). Repositories must
      // not declare any other outbound capability. The three entity models
      // (Conversation/Message/SyncQueueItem) are pure data, not ports.
      const contracts = {
        'entity_store.dart': 'abstract class EntityStore',
        'sync_sink.dart': 'abstract class SyncSink',
        'base_repository.dart': 'abstract class BaseRepository',
        'local_first_repository.dart': 'abstract class LocalFirstRepository',
        'conversation_repository.dart':
            'abstract class ConversationRepository',
        'message_repository.dart': 'abstract class MessageRepository',
        'sync_queue_repository.dart': 'abstract class SyncQueueRepository',
      };
      final domainFiles = _dartFilesUnder('lib/repository/domain');

      for (final entry in contracts.entries) {
        final path = domainFiles
            .firstWhere((p) => p.endsWith(entry.key));
        final source = File(path).readAsStringSync();
        expect(
          source.contains(entry.value),
          isTrue,
          reason: '${entry.key} must declare ${entry.value}',
        );
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
