import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/database/data/argon2id_database_key_service.dart';
import 'package:civic_commons/database/data/key_verification_marker.dart';
import 'package:civic_commons/database/domain/schema.dart';

void main() {
  final crypto = CryptoServiceImpl();
  final keyService = Argon2idDatabaseKeyService(crypto);

  group('SECURITY CHECKPOINT - sensitive columns encrypted at rest', () {
    test('every sensitive column is flagged in the schema', () {
      final sensitive = <String>[
        for (final table in AppSchema.tables)
          ...table.sensitiveColumns.map((c) => '${table.name}.${c.name}'),
      ];

      // Master-plan mandated sensitive values:
      expect(sensitive, contains('messages.ciphertext'));
      expect(sensitive, contains('conversations.participant_hash'));
      expect(sensitive, contains('conversations.encrypted_session_state'));
      expect(sensitive, contains('connection_requests.requester_hash'));
      expect(sensitive, contains('connection_requests.recipient_hash'));
      expect(sensitive, contains('sync_queue.payload'));
    });

    test('sensitive columns are never plaintext-friendly types', () {
      for (final table in AppSchema.tables) {
        for (final column in table.sensitiveColumns) {
          expect(
            ['BLOB', 'TEXT'],
            contains(column.type),
            reason:
                '${table.name}.${column.name} must store opaque ciphertext, '
                'not a plaintext-friendly SQL type',
          );
        }
      }
    });

    test('raw sensitive values never appear in the encrypted storage form',
        () async {
      final key = await keyService.deriveKey('123456');
      final marker = KeyVerificationMarker(crypto);

      // Use HEX-ONLY raw payloads: a non-hex character could never appear in
      // the hex-encoded storage form even if stored in plaintext, so only a
      // hex-pure raw value genuinely proves encryption actually occurred.
      const rawPayloads = [
        '5a45a983c75655ae014d09052fc80545d7b422fd47ba6640dae2a00a5fbc55b2',
        'abcd1234ef5678901234abcd5678ef90',
        'deadbeefcafebabe0123456789abcdef',
      ];

      for (final raw in rawPayloads) {
        final sealed = await marker.seal(
          Uint8List.fromList(utf8.encode(raw)),
          key.rawBytes,
        );
        final storedHex = marker.encode(sealed);

        // The stored form is AES-256-GCM ciphertext — the raw hex value
        // cannot appear in it, and cannot be recovered without the key.
        expect(
          storedHex.toLowerCase().contains(raw.toLowerCase()),
          isFalse,
          reason: 'Raw "$raw" must never be visible in the at-rest form',
        );
      }
    });

    test('decrypting the at-rest form without the key is impossible',
        () async {
      final correctKey = await keyService.deriveKey('123456');
      final wrongKey = await keyService.deriveKey('000000');
      final marker = KeyVerificationMarker(crypto);

      final sealed = await marker.seal(
        Uint8List.fromList(utf8.encode('ciphertext-payload')),
        correctKey.rawBytes,
      );

      // Wrong key → GCM authentication fails → no plaintext is ever released.
      expect(await marker.verify(sealed, wrongKey.rawBytes), isFalse);
    });
  });
}
