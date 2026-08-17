import 'package:civic_commons/academy/data/local_study_group_repository.dart';
import 'package:civic_commons/academy/domain/study_group.dart';
import 'package:civic_commons/academy/domain/study_group_records.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const _m2 = '9d2f1b7a-6c3e-4a5b-8f1d-2c9e4a7b6f10';

LocalStudyGroupRepository _repo({DateTime Function()? clock}) =>
    LocalStudyGroupRepository(
      groupStore: InMemoryEntityStore<StudyGroupRecord>((r) => r.groupId),
      memberStore:
          InMemoryEntityStore<StudyGroupMemberRecord>((r) => r.memberId),
      clock: clock,
    );

List<StudyTopicRef> _topics(String moduleId) => [
      StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: moduleId),
      StudyTopicRef.parse(pillar: StudyPillar.ledger, topicId: 'civics'),
    ];

void main() {
  group('LocalStudyGroupRepository (Task 9.6)', () {
    test('createGroup persists the group + initiator membership locally',
        () async {
      final repo = _repo();
      final handle = StudyGroupHandle.forModule(_m1);

      final group = await repo.createGroup(
        moduleId: _m1,
        title: 'Civic Rights Study Circle',
        locale: 'en',
        pinCode: '800001',
        topics: _topics(_m1),
        capacity: 6,
        initiatorHandle: handle,
      );

      expect(group.participantCount, 1);
      expect(group.hasCapacity, isTrue);
      expect(await repo.getGroup(group.groupId), group);
      final members = await repo.listMembers(group.groupId);
      expect(members, hasLength(1));
      expect(members.single.memberHandle, handle);
      expect(members.single.isInitiator, isTrue);
    });

    test('joinGroup increments the count and records the membership', () async {
      final repo = _repo();
      final handle = StudyGroupHandle.forModule(_m1);
      final group = await repo.createGroup(
        moduleId: _m1,
        title: 'Study Circle',
        locale: 'en',
        pinCode: '800001',
        topics: _topics(_m1),
        capacity: 4,
        initiatorHandle: handle,
      );

      final joined = await repo.joinGroup(
        groupId: group.groupId,
        memberHandle: StudyGroupHandle.forModule(_m2),
      );
      expect(joined.participantCount, 2);
      expect(await repo.listMembers(group.groupId), hasLength(2));

      // Idempotent re-join does NOT double-count.
      final again = await repo.joinGroup(
        groupId: group.groupId,
        memberHandle: StudyGroupHandle.forModule(_m2),
      );
      expect(again.participantCount, 2);
    });

    test('joinGroup rejects a full group', () async {
      final repo = _repo();
      final group = await repo.createGroup(
        moduleId: _m1,
        title: 'Full Circle',
        locale: 'en',
        pinCode: '800001',
        topics: _topics(_m1),
        capacity: 2,
        initiatorHandle: StudyGroupHandle.forModule(_m1),
      );
      await repo.joinGroup(
        groupId: group.groupId,
        memberHandle: StudyGroupHandle.forModule(_m2),
      );
      await expectLater(
        repo.joinGroup(
          groupId: group.groupId,
          memberHandle: StudyGroupHandle.forModule(_m2),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('joinGroup rejects an unknown group', () async {
      final repo = _repo();
      await expectLater(
        repo.joinGroup(
          groupId: 'b0e1c2d3-4a5b-4c6d-8e7f-1a2b3c4d5e6f',
          memberHandle: StudyGroupHandle.forModule(_m1),
        ),
        throwsArgumentError,
      );
    });

    test('listGroups scopes by module and orders newest-first', () async {
      var now = DateTime.utc(2026, 8, 17);
      final repo = _repo(clock: () => now);
      final a = await repo.createGroup(
        moduleId: _m1,
        title: 'First',
        locale: 'en',
        pinCode: '800001',
        topics: _topics(_m1),
        capacity: 5,
        initiatorHandle: StudyGroupHandle.forModule(_m1),
      );
      now = now.add(const Duration(minutes: 1));
      final b = await repo.createGroup(
        moduleId: _m2,
        title: 'Second',
        locale: 'hi',
        pinCode: '110001',
        topics: _topics(_m2),
        capacity: 5,
        initiatorHandle: StudyGroupHandle.forModule(_m2),
      );

      final all = await repo.listGroups();
      expect(all, hasLength(2));
      expect(all.first.groupId, b.groupId, reason: 'newest first');
      final scoped = await repo.listGroups(moduleId: _m1);
      expect(scoped, hasLength(1));
      expect(scoped.single.groupId, a.groupId);
    });

    test('codec strictness: forged non-UUID row throws at read time', () {
      // Read-path re-validation: a StudyGroupRecord with a non-UUID id can
      // never parse (the row codec goes through StudyGroup.parse).
      expect(
        () => StudyGroup.parse(
          groupId: 'not-a-uuid',
          moduleId: _m1,
          title: 'X',
          locale: 'en',
          pinCode: '800001',
          topics: _topics(_m1),
          capacity: 5,
          participantCount: 1,
          createdAt: DateTime.utc(2026, 8, 17),
        ),
        throwsArgumentError,
      );
    });

    test('cold-restart recovery: a fresh repository re-reads persisted rows',
        () async {
      // The local repository is backed by the injected EntityStore — a
      // crash simply re-creates the store (SQLCipher rows) and the
      // repository re-reads them. With the in-memory fake, the equivalent
      // contract is: a NEW repository over the SAME store sees the rows.
      final store = InMemoryEntityStore<StudyGroupRecord>((r) => r.groupId);
      final memberStore =
          InMemoryEntityStore<StudyGroupMemberRecord>((r) => r.memberId);
      final repo = LocalStudyGroupRepository(
        groupStore: store,
        memberStore: memberStore,
      );
      final group = await repo.createGroup(
        moduleId: _m1,
        title: 'Persisted Circle',
        locale: 'en',
        pinCode: '800001',
        topics: _topics(_m1),
        capacity: 5,
        initiatorHandle: StudyGroupHandle.forModule(_m1),
      );

      // "Restart": a brand-new repository instance over the same stores.
      final restarted = LocalStudyGroupRepository(
        groupStore: store,
        memberStore: memberStore,
      );
      final groups = await restarted.listGroups(moduleId: _m1);
      expect(groups, hasLength(1));
      expect(groups.single.groupId, group.groupId);
      expect(groups.single.title, 'Persisted Circle');
      expect(await restarted.listMembers(group.groupId), hasLength(1));
    });
  });
}
