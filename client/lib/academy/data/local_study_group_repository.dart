import '../../repository/domain/entity_store.dart';
import '../../repository/domain/idempotency_key.dart';
import '../domain/study_group.dart';
import '../domain/study_group_records.dart';

/// Production [StudyGroupRepository] (Task 9.6 — Cross-Pillar Study Group
/// Matching).
///
/// Persists study groups + the local membership rows inside the encrypted
/// SQLCipher database (`study_groups` + `study_group_members`, schema v13).
/// OFFLINE-FIRST: the local rows are written before anything else — a group
/// creation or join lands in the encrypted partition immediately and the
/// sealed sync enqueue happens through the wrapping [QueueStudyGroupSink].
///
/// SECURITY CHECKPOINT (Task 9.6): every group/member id is a minted UUID
/// v4; participant handles are the deterministic `SG-####` pseudonymous
/// handles derived from the anchor module id — zero identity ever enters
/// these rows; the pin-code column is flagged sensitive (the same coarse
/// civic scope as the Ledger feed).
class LocalStudyGroupRepository implements StudyGroupRepository {
  final EntityStore<StudyGroupRecord> _groupStore;
  final EntityStore<StudyGroupMemberRecord> _memberStore;
  final IdempotencyKeyGenerator _idGen;
  final DateTime Function() _clock;

  LocalStudyGroupRepository({
    required EntityStore<StudyGroupRecord> groupStore,
    required EntityStore<StudyGroupMemberRecord> memberStore,
    IdempotencyKeyGenerator? idempotencyKeys,
    DateTime Function()? clock,
  })  : _groupStore = groupStore,
        _memberStore = memberStore,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _clock = clock ?? DateTime.now;

  @override
  Future<List<StudyGroup>> listGroups({String? moduleId}) async {
    final records = await _groupStore.getAll();
    final groups = records
        .map(_groupFromRecord)
        .where((g) => moduleId == null || g.moduleId == moduleId)
        .toList();
    // Newest-created first.
    groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return groups;
  }

  @override
  Future<StudyGroup?> getGroup(String groupId) async {
    final record = await _groupStore.getById(groupId);
    return record == null ? null : _groupFromRecord(record);
  }

  @override
  Future<List<StudyGroupMember>> listMembers(String groupId) async {
    final records = await _memberStore.getAll();
    final members = records
        .where((m) => m.groupId == groupId)
        .map(_memberFromRecord)
        .toList();
    // Initiator first, then join order.
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
    // Local-first: the initiator membership row lands first, then the group
    // aggregate.
    await _memberStore.insert(StudyGroupMemberRecord(
      memberId: _idGen.generate(),
      groupId: groupId,
      memberHandle: initiatorHandle,
      isInitiator: true,
      joinedAt: now,
    ));
    await _groupStore.insert(StudyGroupRecord(
      groupId: groupId,
      moduleId: moduleId,
      title: title.trim(),
      locale: locale,
      pinCode: pinCode,
      topics: topics,
      capacity: capacity,
      participantCount: 1,
      createdAt: now,
    ));
    return (await getGroup(groupId))!;
  }

  @override
  Future<StudyGroup> joinGroup({
    required String groupId,
    required String memberHandle,
  }) async {
    final record = await _groupStore.getById(groupId);
    if (record == null) {
      throw ArgumentError('Study group not found: $groupId');
    }
    final group = _groupFromRecord(record);
    if (!group.hasCapacity) {
      throw StateError('Study group is full');
    }
    // Idempotent join: if this device already has a membership row for the
    // group (e.g. re-join after a crash), do not double-count.
    final existing = (await _memberStore.getAll())
        .where((m) => m.groupId == groupId)
        .map(_memberFromRecord)
        .toList();
    final alreadyJoined = existing.any((m) => m.memberHandle == memberHandle);
    if (!alreadyJoined) {
      await _memberStore.insert(StudyGroupMemberRecord(
        memberId: _idGen.generate(),
        groupId: groupId,
        memberHandle: memberHandle,
        isInitiator: false,
        joinedAt: _clock(),
      ));
    }
    await _groupStore.update(StudyGroupRecord(
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
    ));
    return (await getGroup(groupId))!;
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
