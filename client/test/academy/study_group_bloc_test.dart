import 'package:civic_commons/academy/data/in_memory_study_group_repository.dart';
import 'package:civic_commons/academy/domain/study_group.dart';
import 'package:civic_commons/state/data/local_study_group_bloc.dart';
import 'package:civic_commons/state/domain/study_group_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

void main() {
  group('LocalStudyGroupBloc (Task 9.6)', () {
    test('start loads groups, memberships and the deterministic matches',
        () async {
      final repo = InMemoryStudyGroupRepository();
      await repo.seedGroup(
        moduleId: _m1,
        title: 'Civic Rights Study Circle',
        locale: 'en',
        pinCode: '800001',
        topics: [
          StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: _m1),
          StudyTopicRef.parse(pillar: StudyPillar.ledger, topicId: 'civics'),
        ],
        capacity: 6,
      );
      final bloc = LocalStudyGroupBloc(repository: repo);
      addTearDown(bloc.close);

      await bloc.start(moduleId: _m1, pinCode: '800001', locale: 'en');
      final state = bloc.current;

      expect(state.phase, StudyGroupPhase.ready);
      expect(state.groups, hasLength(1));
      expect(state.participantHandle, StudyGroupHandle.forModule(_m1));
      expect(state.matches, hasLength(1));
      expect(state.matches.single.group.title, 'Civic Rights Study Circle');
      expect(state.matches.single.score, greaterThan(0));
      // No identity in state.
      expect(state.pinCode, '800001');
      expect(state.locale, 'en');
    });

    test('failure surfaces a GENERIC error (no side channel)', () async {
      final bloc = LocalStudyGroupBloc(
        repository: _ThrowingStudyGroupRepository(),
      );
      addTearDown(bloc.close);

      await bloc.start(moduleId: _m1, pinCode: '800001', locale: 'en');
      expect(bloc.current.phase, StudyGroupPhase.failure);
      expect(bloc.current.errorMessage,
          'Unable to load study groups. Please try again.');
    });
    test('retry recovers after a transient failure', () async {
      final repo = _FlakyStudyGroupRepository();
      final bloc = LocalStudyGroupBloc(repository: repo);
      addTearDown(bloc.close);

      await bloc.start(moduleId: _m1, pinCode: '800001', locale: 'en');
      expect(bloc.current.phase, StudyGroupPhase.failure);

      await bloc.retry();
      expect(bloc.current.phase, StudyGroupPhase.ready);
      expect(bloc.current.groups, hasLength(1));
    });

    test('start emits through the state stream for late subscribers', () async {
      final repo = InMemoryStudyGroupRepository();
      final bloc = LocalStudyGroupBloc(repository: repo);
      addTearDown(bloc.close);

      final states = <StudyGroupPhase>[];
      bloc.state.listen((s) => states.add(s.phase));
      await bloc.start(moduleId: _m1, pinCode: '800001', locale: 'en');
      // Broadcast delivery is scheduled as microtasks — drain them.
      await Future<void>.delayed(Duration.zero);

      expect(states,
          containsAll([StudyGroupPhase.loading, StudyGroupPhase.ready]));
      expect(bloc.current.phase, StudyGroupPhase.ready);
    });

    test('search filters groups by title', () async {
      final repo = InMemoryStudyGroupRepository();
      await repo.seedGroup(
        moduleId: _m1,
        title: 'Civic Rights Circle',
        locale: 'en',
        pinCode: '800001',
        topics: [
          StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: _m1),
        ],
        capacity: 5,
      );
      await repo.seedGroup(
        moduleId: _m1,
        title: 'Constitution Jam',
        locale: 'en',
        pinCode: '800001',
        topics: [
          StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: _m1),
        ],
        capacity: 5,
      );
      final bloc = LocalStudyGroupBloc(repository: repo);
      addTearDown(bloc.close);
      await bloc.start(moduleId: _m1, pinCode: '800001', locale: 'en');

      bloc.search('constitution');
      expect(bloc.current.filteredGroups, hasLength(1));
      expect(bloc.current.filteredGroups.single.title, 'Constitution Jam');

      bloc.search('');
      expect(bloc.current.filteredGroups, hasLength(2));
    });

    test('createGroup persists locally and refreshes the snapshot', () async {
      final repo = InMemoryStudyGroupRepository();
      final bloc = LocalStudyGroupBloc(repository: repo);
      addTearDown(bloc.close);
      await bloc.start(moduleId: _m1, pinCode: '800001', locale: 'en');

      await bloc.createGroup(
        title: 'New Circle',
        topics: [
          StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: _m1),
        ],
        capacity: 4,
      );

      expect(bloc.current.phase, StudyGroupPhase.ready);
      expect(bloc.current.groups, hasLength(1));
      expect(bloc.current.groups.single.title, 'New Circle');
      expect(
          bloc.current.hasJoined(bloc.current.groups.single.groupId), isTrue);
    });

    test('joinGroup updates membership and participant count', () async {
      final repo = InMemoryStudyGroupRepository();
      final group = await repo.seedGroup(
        moduleId: _m1,
        title: 'Civic Circle',
        locale: 'en',
        pinCode: '800001',
        topics: [
          StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: _m1),
        ],
        capacity: 5,
      );
      final bloc = LocalStudyGroupBloc(repository: repo);
      addTearDown(bloc.close);
      // The seeded group is anchored on _m1 — the bloc must scope to that
      // module for the group to appear in the snapshot.
      await bloc.start(moduleId: _m1, pinCode: '800001', locale: 'en');

      await bloc.joinGroup(group.groupId);

      expect(bloc.current.hasJoined(group.groupId), isTrue);
      final updated =
          bloc.current.groups.firstWhere((g) => g.groupId == group.groupId);
      expect(updated.participantCount, 2);
    });
  });
}

class _ThrowingStudyGroupRepository implements StudyGroupRepository {
  @override
  Future<List<StudyGroup>> listGroups({String? moduleId}) async =>
      throw StateError('boom');

  @override
  Future<StudyGroup?> getGroup(String groupId) async =>
      throw StateError('boom');

  @override
  Future<List<StudyGroupMember>> listMembers(String groupId) async =>
      throw StateError('boom');

  @override
  Future<StudyGroup> createGroup({
    required String moduleId,
    required String title,
    required String locale,
    required String pinCode,
    required List<StudyTopicRef> topics,
    required int capacity,
    required String initiatorHandle,
  }) async =>
      throw StateError('boom');

  @override
  Future<StudyGroup> joinGroup({
    required String groupId,
    required String memberHandle,
  }) async =>
      throw StateError('boom');
}

class _FlakyStudyGroupRepository implements StudyGroupRepository {
  bool _first = true;

  @override
  Future<List<StudyGroup>> listGroups({String? moduleId}) async {
    if (_first) {
      _first = false;
      throw StateError('transient');
    }
    return [
      StudyGroup.parse(
        groupId: 'fffffff1-ffff-4fff-8fff-ffffffffffff',
        moduleId: _m1,
        title: 'Recovered Circle',
        locale: 'en',
        pinCode: '800001',
        topics: [
          StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: _m1),
        ],
        capacity: 5,
        participantCount: 1,
        createdAt: DateTime.utc(2026, 8, 17),
      ),
    ];
  }

  @override
  Future<StudyGroup?> getGroup(String groupId) async => null;

  @override
  Future<List<StudyGroupMember>> listMembers(String groupId) async => const [];

  @override
  Future<StudyGroup> createGroup({
    required String moduleId,
    required String title,
    required String locale,
    required String pinCode,
    required List<StudyTopicRef> topics,
    required int capacity,
    required String initiatorHandle,
  }) =>
      throw StateError('not implemented');

  @override
  Future<StudyGroup> joinGroup({
    required String groupId,
    required String memberHandle,
  }) async =>
      throw StateError('not implemented');
}
