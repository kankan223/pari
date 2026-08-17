import 'package:civic_commons/academy/data/local_study_group_repository.dart';
import 'package:civic_commons/academy/data/queue_study_group_sink.dart';
import 'package:civic_commons/academy/domain/study_group.dart';
import 'package:civic_commons/academy/domain/study_group_records.dart';
import 'package:civic_commons/academy/domain/study_group_wire_codec.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const _m2 = '9d2f1b7a-6c3e-4a5b-8f1d-2c9e4a7b6f10';

List<StudyTopicRef> _topics(String moduleId) => [
      StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: moduleId),
      StudyTopicRef.parse(pillar: StudyPillar.ledger, topicId: 'civics'),
    ];

void main() {
  group('QueueStudyGroupSink (Task 9.6 — encrypted before sync)', () {
    test('createGroup is local-first AND enqueues a SEALED frame', () async {
      final cipher = testCipher(); // real fast AES-256-GCM
      final syncQueue = LocalSyncQueueRepository(
        store: queueStore(),
        cipher: cipher,
      );
      final local = LocalStudyGroupRepository(
        groupStore: InMemoryEntityStore<StudyGroupRecord>((r) => r.groupId),
        memberStore:
            InMemoryEntityStore<StudyGroupMemberRecord>((r) => r.memberId),
      );
      final sink = QueueStudyGroupSink(local: local, syncQueue: syncQueue);
      final handle = StudyGroupHandle.forModule(_m1);

      final group = await sink.createGroup(
        moduleId: _m1,
        title: 'Civic Rights Study Circle',
        locale: 'en',
        pinCode: '800001',
        topics: _topics(_m1),
        capacity: 6,
        initiatorHandle: handle,
      );

      // 1. Local-first: the group + initiator row exist immediately.
      expect(await local.getGroup(group.groupId), isNotNull);
      expect(await local.listMembers(group.groupId), hasLength(1));

      // 2. One sealed queue item is enqueued.
      final pending = await syncQueue.getPending();
      expect(pending, hasLength(1));

      // 3. Opening the sealed payload yields the exact frame.
      final opened = await cipher.open(pending.single.payload);
      final frame = decodeStudyGroupFrame(opened);
      expect(frame.groupId, group.groupId);
      expect(frame.moduleId, _m1);
      expect(frame.title, 'Civic Rights Study Circle');
      expect(frame.pinCode, '800001');
      expect(frame.memberHandle, handle);
      expect(frame.isInitiator, isTrue);
      expect(frame.isJoin, isFalse);
      expect(frame.createdAtMs, greaterThan(0));

      // 4. BYTE-LEVEL: the STORED queue payload is ciphertext — it can
      //    never equal the plaintext frame bytes the sink would have
      //    serialized (re-encoded from the opened frame).
      final plaintext = encodeStudyGroupFrame(frame);
      expect(pending.single.payload, isNot(equals(plaintext)));
      expect(pending.single.payload, isNotEmpty);
    });

    test('joinGroup enqueues a sealed JOIN frame', () async {
      final cipher = testCipher();
      final syncQueue = LocalSyncQueueRepository(
        store: queueStore(),
        cipher: cipher,
      );
      final local = LocalStudyGroupRepository(
        groupStore: InMemoryEntityStore<StudyGroupRecord>((r) => r.groupId),
        memberStore:
            InMemoryEntityStore<StudyGroupMemberRecord>((r) => r.memberId),
      );
      final sink = QueueStudyGroupSink(local: local, syncQueue: syncQueue);

      final group = await sink.createGroup(
        moduleId: _m1,
        title: 'Study Circle',
        locale: 'en',
        pinCode: '800001',
        topics: _topics(_m1),
        capacity: 5,
        initiatorHandle: StudyGroupHandle.forModule(_m1),
      );
      await sink.joinGroup(
        groupId: group.groupId,
        memberHandle: StudyGroupHandle.forModule(_m2),
      );

      final pending = await syncQueue.getPending();
      expect(pending, hasLength(2)); // create + join.
      final joined = await local.getGroup(group.groupId);
      expect(joined!.participantCount, 2);

      final opened = await cipher.open(pending[1].payload);
      final frame = decodeStudyGroupFrame(opened);
      expect(frame.isJoin, isTrue);
      expect(frame.isInitiator, isFalse);
      expect(frame.groupId, group.groupId);
    });
  });
}
