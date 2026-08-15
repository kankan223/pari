import 'dart:convert' as convert;

import 'package:civic_commons/repository/data/local_connection_request_repository.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/connection_request.dart';
import 'package:civic_commons/repository/domain/entity_store.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// VERIFY (Task 6.2): the connection-request repository is local-first —
/// mutations persist to the encrypted store + enqueue a sync mutation
/// immediately, state transitions follow the single-transition rule, targets
/// must be 64-hex blind hashes (a raw phone can never enter storage or the
/// queue), and the sync envelopes carry no PII.
void main() {
  const alice =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const bob =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const carol =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

  InMemoryEntityStore<ConnectionRequest> store() =>
      InMemoryEntityStore((r) => r.id);

  LocalConnectionRequestRepository repo({
    required EntityStore<ConnectionRequest> entityStore,
    required LocalSyncQueueRepository queue,
  }) =>
      LocalConnectionRequestRepository(
        store: entityStore,
        syncQueue: queue,
      );

  group('send - offline-first + idempotent while pending', () {
    test('send persists pending + enqueues one create mutation', () async {
      final storeA = store();
      final queue =
          LocalSyncQueueRepository(store: queueStore(), cipher: testCipher());
      final r = repo(entityStore: storeA, queue: queue);

      final request = await r.send(requesterHash: alice, targetHash: bob);

      expect(request.requesterHash, alice);
      expect(request.recipientHash, bob);
      expect(request.status, ConnectionRequestStatus.pending);
      expect((await storeA.getAll()).single.id, request.id);

      final queued = await queue.getPending();
      expect(queued, hasLength(1));
      expect(queued.single.operationType, SyncOperationType.create);
    });

    test('send is idempotent while pending (same pair, same request)',
        () async {
      final storeA = store();
      final queue =
          LocalSyncQueueRepository(store: queueStore(), cipher: testCipher());
      final r = repo(entityStore: storeA, queue: queue);

      final first = await r.send(requesterHash: alice, targetHash: bob);
      final second = await r.send(requesterHash: alice, targetHash: bob);

      expect(second.id, first.id);
      expect(await storeA.getAll(), hasLength(1));
      expect(await queue.getPending(), hasLength(1));
    });

    test('send rejects non-blind-hash targets (raw phone can never queue)',
        () async {
      final storeA = store();
      final queue =
          LocalSyncQueueRepository(store: queueStore(), cipher: testCipher());
      final r = repo(entityStore: storeA, queue: queue);

      for (final bad in [
        '+14155552671',
        'alice',
        'A' * 64, // uppercase hex is rejected (lowercase only)
        'a' * 63,
      ]) {
        await expectLater(
          r.send(requesterHash: alice, targetHash: bad),
          throwsArgumentError,
        );
      }
      expect(await storeA.getAll(), isEmpty);
      expect(await queue.getPending(), isEmpty);
    });
  });

  group('state machine - single transition, terminal immutable', () {
    test('accept moves pending → accepted and enqueues an update', () async {
      final storeA = store();
      final queue =
          LocalSyncQueueRepository(store: queueStore(), cipher: testCipher());
      final r = repo(entityStore: storeA, queue: queue);
      final request = await r.send(requesterHash: alice, targetHash: bob);

      final accepted = await r.accept(request.id);

      expect(accepted.status, ConnectionRequestStatus.accepted);
      expect((await storeA.getById(request.id))!.status,
          ConnectionRequestStatus.accepted);
      final queued = await queue.getPending();
      expect(queued, hasLength(2));
      expect(queued.last.operationType, SyncOperationType.update);
    });

    test('a second accept on the same request throws (CAS rule)', () async {
      final storeA = store();
      final queue =
          LocalSyncQueueRepository(store: queueStore(), cipher: testCipher());
      final r = repo(entityStore: storeA, queue: queue);
      final request = await r.send(requesterHash: alice, targetHash: bob);
      await r.accept(request.id);

      await expectLater(r.accept(request.id), throwsStateError);
    });

    test('reject + withdraw transition once, then throw', () async {
      final storeA = store();
      final queue =
          LocalSyncQueueRepository(store: queueStore(), cipher: testCipher());
      final r = repo(entityStore: storeA, queue: queue);

      final req1 = await r.send(requesterHash: alice, targetHash: bob);
      final rejected = await r.reject(req1.id);
      expect(rejected.status, ConnectionRequestStatus.rejected);
      await expectLater(r.reject(req1.id), throwsStateError);

      final req2 = await r.send(requesterHash: bob, targetHash: carol);
      final withdrawn = await r.withdraw(req2.id);
      expect(withdrawn.status, ConnectionRequestStatus.withdrawn);
      await expectLater(r.withdraw(req2.id), throwsStateError);
    });

    test('transition on unknown id throws', () async {
      final storeA = store();
      final queue =
          LocalSyncQueueRepository(store: queueStore(), cipher: testCipher());
      final r = repo(entityStore: storeA, queue: queue);
      await expectLater(r.accept('missing'), throwsStateError);
    });
  });

  group('inbox queries', () {
    test('listIncomingPending returns only pending requests targeting the user',
        () async {
      final storeA = store();
      final queue =
          LocalSyncQueueRepository(store: queueStore(), cipher: testCipher());
      final r = repo(entityStore: storeA, queue: queue);

      await r.send(requesterHash: alice, targetHash: bob);
      final incoming2 = await r.send(requesterHash: carol, targetHash: bob);
      await r.send(requesterHash: bob, targetHash: alice); // bob is requester

      final inbox = await r.listIncomingPending(bob);
      expect(inbox, hasLength(2));

      // Accept one → it leaves the inbox.
      await r.accept(incoming2.id);
      final after = await r.listIncomingPending(bob);
      expect(after, hasLength(1));
      expect(after.single.requesterHash, alice);
    });
  });

  group('row codec (SQLCipher boundary)', () {
    test('connectionRequestToRow/FromRow round-trips every field', () {
      const request = ConnectionRequest(
        id: 'req-1',
        requesterHash: alice,
        recipientHash: bob,
        status: ConnectionRequestStatus.pending,
      );
      final row = connectionRequestToRow(request);
      expect(row['id'], 'req-1');
      expect(row['requester_hash'], alice);
      expect(row['recipient_hash'], bob);
      expect(row['status'], 'pending');

      final restored = connectionRequestFromRow(row);
      expect(restored.id, request.id);
      expect(restored.requesterHash, request.requesterHash);
      expect(restored.recipientHash, request.recipientHash);
      expect(restored.status, request.status);
    });

    test('status round-trips all wire names', () {
      for (final status in ConnectionRequestStatus.values) {
        final restored =
            connectionRequestFromRow(connectionRequestToRow(ConnectionRequest(
          id: 'r',
          requesterHash: alice,
          recipientHash: bob,
          status: status,
        )));
        expect(restored.status, status);
      }
    });
  });

  group('SECURITY CHECKPOINT - sync envelopes carry no PII', () {
    test('enqueued envelope contains only blind hashes + status', () async {
      final queue =
          LocalSyncQueueRepository(store: queueStore(), cipher: testCipher());
      final r = repo(
        entityStore: store(),
        queue: queue,
      );
      await r.send(requesterHash: alice, targetHash: bob);

      final queued = await queue.getPending();
      // The queue cipher sealed the payload; the STORE only ever holds
      // ciphertext. Decrypt it back and assert the plaintext envelope.
      final plaintext = await testCipher().open(queued.single.payload);
      final envelope = convert.jsonDecode(convert.utf8.decode(plaintext))
          as Map<String, dynamic>;
      expect(envelope['action'], 'send');
      expect(envelope['requester_hash'], alice);
      expect(envelope['recipient_hash'], bob);
      expect(envelope['status'], 'pending');
      // No phone-shaped or username-shaped content anywhere in the envelope.
      // NOTE: a bare `\d{6,}` digit-run check is intentionally NOT used here
      // — random UUID v4s contain 6+ consecutive hex digits ~2% of the time,
      // which would make this test flaky. Instead each value is asserted to
      // have its exact safe shape (structural proof, never flaky):
      // fixed tokens, a UUID, and 64-hex blind hashes.
      expect(envelope.keys.toSet(), {
        'action',
        'id',
        'requester_hash',
        'recipient_hash',
        'status',
      });
      expect(envelope['action'], 'send');
      expect(envelope['status'], 'pending');
      expect(isBlindHashId(envelope['requester_hash'] as String), isTrue);
      expect(isBlindHashId(envelope['recipient_hash'] as String), isTrue);
      final id = envelope['id'] as String;
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
                r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(id),
        isTrue,
        reason: 'id must be a RFC 4122 UUID v4, not a phone or other PII',
      );
      // No phone-shaped or email-shaped content in any value.
      final joined = envelope.values.join('|');
      expect(RegExp(r'\+\d{8,}').hasMatch(joined), isFalse);
      expect(RegExp(r'@|\w+\.\w+').hasMatch(joined), isFalse);
    });
  });

  group('blind-hash validator', () {
    test('isBlindHashId accepts only 64 lowercase hex chars', () {
      expect(isBlindHashId(alice), isTrue);
      expect(isBlindHashId('a' * 64), isTrue);
      expect(isBlindHashId('A' * 64), isFalse);
      expect(isBlindHashId('g' * 64), isFalse);
      expect(isBlindHashId('a' * 63), isFalse);
      expect(isBlindHashId('a' * 65), isFalse);
      expect(isBlindHashId(''), isFalse);
      expect(isBlindHashId('+14155552671'), isFalse);
    });
  });
}
