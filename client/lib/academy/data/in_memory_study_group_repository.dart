import '../../repository/domain/idempotency_key.dart';
import '../domain/study_group.dart';
import '../domain/study_group_records.dart';

/// In-memory [StudyGroupRepository] for the harness and widget tests.
///
/// Same semantics as [LocalStudyGroupRepository] (offline-first group +
/// membership rows, UUID v4 id minting, `SG-####` handles, capacity +
/// idempotent joins) but backed by plain maps — no SQLCipher, no persistence
/// across restarts. The production wiring injects the SQLCipher-backed local
/// repository at the Phase-9 composition root.
class InMemoryStudyGroupRepository implements StudyGroupRepository {
  final Map<String, StudyGroupRecord> _groups = {};
  final Map<String, StudyGroupMemberRecord> _members = {};
  final IdempotencyKeyGenerator _idGen;
  final DateTime Function() _clock;

  InMemoryStudyGroupRepository({
    IdempotencyKeyGenerator? idempotencyKeys,
    DateTime Function()? clock,
  })  : _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _clock = clock ?? DateTime.now;

  /// Seeds a group (used by tests + the harness to demo matching).
  Future<StudyGroup> seedGroup({
    required String moduleId,
    required String title,
    required String locale,
    required String pinCode,
    required List<StudyTopicRef> topics,
    required int capacity,
    String? groupId,
  }) async {
    final record = StudyGroupRecord(
      groupId: groupId ?? _idGen.generate(),
      moduleId: moduleId,
      title: title,
      locale: locale,
      pinCode: pinCode,
      topics: topics,
      capacity: capacity,
      participantCount: 1,
      createdAt: _clock(),
    );
    _groups[record.groupId] = record;
    return _groupFromRecord(record);
  }

  @override
  Future<List<StudyGroup>> listGroups({String? moduleId}) async {
    final groups = _groups.values
        .map(_groupFromRecord)
        .where((g) => moduleId == null || g.moduleId == moduleId)
        .toList();
    groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return groups;
  }

  @override
  Future<StudyGroup?> getGroup(String groupId) async {
    final record = _groups[groupId];
    return record == null ? null : _groupFromRecord(record);
  }

  @override
  Future<List<StudyGroupMember>> listMembers(String groupId) async {
    final members = _members.values
        .where((m) => m.groupId == groupId)
        .map(_memberFromRecord)
        .toList();
    members.sort((a, b) {
      if (a.isInitiator != b.isInitiator) {
        return a.isInitiator ? -1 : 1;
      }
      return a.joinedAt.compareTo(b.joinedAt);
    });
    return members;
  }

  @override
  Future<StudyGroup> createGroup({
    required String moduleId,
    required String title,
    required String locale,
    required String pinCode,
    required List<StudyTopicRef> topics,
    required int capacity,
    required String initiatorHandle,
  }) async {
    final now = _clock();
    final groupId = _idGen.generate();
    _members[_idGen.generate()] = StudyGroupMemberRecord(
      memberId: _idGen.generate(),
      groupId: groupId,
      memberHandle: initiatorHandle,
      isInitiator: true,
      joinedAt: now,
    );
    _groups[groupId] = StudyGroupRecord(
      groupId: groupId,
      moduleId: moduleId,
      title: title.trim(),
      locale: locale,
      pinCode: pinCode,
      topics: topics,
      capacity: capacity,
      participantCount: 1,
      createdAt: now,
    );
    return _groupFromRecord(_groups[groupId]!);
  }

  @override
  Future<StudyGroup> joinGroup({
    required String groupId,
    required String memberHandle,
  }) async {
    final record = _groups[groupId];
    if (record == null) {
      throw ArgumentError('Study group not found: $groupId');
    }
    final group = _groupFromRecord(record);
    if (!group.hasCapacity) {
      throw StateError('Study group is full');
    }
    final existing = _members.values
        .where((m) => m.groupId == groupId)
        .map(_memberFromRecord)
        .toList();
    final alreadyJoined = existing.any((m) => m.memberHandle == memberHandle);
    if (!alreadyJoined) {
      _members[_idGen.generate()] = StudyGroupMemberRecord(
        memberId: _idGen.generate(),
        groupId: groupId,
        memberHandle: memberHandle,
        isInitiator: false,
        joinedAt: _clock(),
      );
    }
    _groups[groupId] = StudyGroupRecord(
      groupId: group.groupId,
      moduleId: group.moduleId,
      title: group.title,
      locale: group.locale,
      pinCode: group.pinCode,
      topics: group.topics,
      capacity: group.capacity,
      participantCount:
          alreadyJoined ? group.participantCount : group.participantCount + 1,
      createdAt: group.createdAt,
    );
    return _groupFromRecord(_groups[groupId]!);
  }

  static StudyGroup _groupFromRecord(StudyGroupRecord r) => StudyGroup.parse(
        groupId: r.groupId,
        moduleId: r.moduleId,
        title: r.title,
        locale: r.locale,
        pinCode: r.pinCode,
        topics: r.topics,
        capacity: r.capacity,
        participantCount: r.participantCount,
        createdAt: r.createdAt,
      );

  static StudyGroupMember _memberFromRecord(StudyGroupMemberRecord r) =>
      StudyGroupMember.parse(
        memberId: r.memberId,
        groupId: r.groupId,
        memberHandle: r.memberHandle,
        isInitiator: r.isInitiator,
        joinedAt: r.joinedAt,
      );
}
