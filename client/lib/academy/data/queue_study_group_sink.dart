import '../../repository/domain/sync_queue_item.dart';
import '../../repository/domain/sync_queue_repository.dart';
import '../domain/study_group.dart';
import '../domain/study_group_wire_codec.dart';

/// Sealed sync wrapper around [StudyGroupRepository] (Task 9.6).
///
/// Every group mutation is persisted locally FIRST (offline-first, via the
/// injected [StudyGroupRepository] — the SQLCipher-backed local rows) and
/// then a [SyncQueueItem] is enqueued with the serialized mutation frame;
/// the [SyncQueueRepository] SEALS the payload with the AES-256-GCM queue
/// cipher BEFORE storage (SECURITY CHECKPOINT Task 9.6: study group data is
/// encrypted before sync) — the queue never persists plaintext group frames.
///
/// Reads delegate to the local repository; writes are local-first + queued.
class QueueStudyGroupSink implements StudyGroupRepository {
  final StudyGroupRepository _local;
  final SyncQueueRepository _syncQueue;

  QueueStudyGroupSink({
    required StudyGroupRepository local,
    required SyncQueueRepository syncQueue,
  })  : _local = local,
        _syncQueue = syncQueue;

  @override
  Future<List<StudyGroup>> listGroups({String? moduleId}) =>
      _local.listGroups(moduleId: moduleId);

  @override
  Future<StudyGroup?> getGroup(String groupId) => _local.getGroup(groupId);

  @override
  Future<List<StudyGroupMember>> listMembers(String groupId) =>
      _local.listMembers(groupId);

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
    // 1. Local-first write — persist inside the encrypted DB immediately.
    final group = await _local.createGroup(
      moduleId: moduleId,
      title: title,
      locale: locale,
      pinCode: pinCode,
      topics: topics,
      capacity: capacity,
      initiatorHandle: initiatorHandle,
    );
    // 2. Queue the mutation — the frame carries ONLY UUID ids + public
    //    fields + the coarse pin scope + the SG-#### handle, SEALED by the
    //    queue repository.
    await _queueFrame(
      group: group,
      memberHandle: initiatorHandle,
      isInitiator: true,
      isJoin: false,
    );
    return group;
  }

  @override
  Future<StudyGroup> joinGroup({
    required String groupId,
    required String memberHandle,
  }) async {
    // 1. Local-first write.
    final group = await _local.joinGroup(
      groupId: groupId,
      memberHandle: memberHandle,
    );
    // 2. Queue the join mutation, SEALED.
    await _queueFrame(
      group: group,
      memberHandle: memberHandle,
      isInitiator: false,
      isJoin: true,
    );
    return group;
  }

  Future<void> _queueFrame({
    required StudyGroup group,
    required String memberHandle,
    required bool isInitiator,
    required bool isJoin,
  }) async {
    final frame = StudyGroupWireFrame(
      groupId: group.groupId,
      moduleId: group.moduleId,
      title: group.title,
      locale: group.locale,
      pinCode: group.pinCode,
      topics: group.topics,
      capacity: group.capacity,
      memberHandle: memberHandle,
      isInitiator: isInitiator,
      isJoin: isJoin,
      createdAtMs: group.createdAt.millisecondsSinceEpoch,
    );
    await _syncQueue.enqueue(
      operationType:
          isJoin ? SyncOperationType.update : SyncOperationType.create,
      payload: encodeStudyGroupFrame(frame),
    );
  }
}
