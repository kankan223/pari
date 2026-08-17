import 'study_group.dart';

/// Locally-persisted study group row (Task 9.6).
///
/// Persisted inside the encrypted SQLCipher database (`study_groups`,
/// schema v13).
///
/// SECURITY CHECKPOINT (Task 9.6): the row carries ONLY a validated UUID v4
/// group id, the anchor module's UUID v4, a public title, a locale tag, the
/// coarse civic pin-code scope, the cross-pillar topic refs, a capacity and
/// a participant count — zero identity columns, no participant handles (the
/// members live in `study_group_members`).
class StudyGroupRecord {
  final String groupId;
  final String moduleId;
  final String title;
  final String locale;
  final String pinCode;
  final List<StudyTopicRef> topics;
  final int capacity;
  final int participantCount;
  final DateTime createdAt;

  const StudyGroupRecord({
    required this.groupId,
    required this.moduleId,
    required this.title,
    required this.locale,
    required this.pinCode,
    required this.topics,
    required this.capacity,
    required this.participantCount,
    required this.createdAt,
  });
}

/// A locally-persisted study group member row (Task 9.6).
///
/// Persisted inside the encrypted SQLCipher database
/// (`study_group_members`, schema v13) — the LOCAL device's membership rows.
///
/// SECURITY CHECKPOINT (Task 9.6): the row carries ONLY the member's
/// blinded deterministic `SG-####` handle — never identity.
class StudyGroupMemberRecord {
  final String memberId;
  final String groupId;
  final String memberHandle;
  final bool isInitiator;
  final DateTime joinedAt;

  const StudyGroupMemberRecord({
    required this.memberId,
    required this.groupId,
    required this.memberHandle,
    required this.isInitiator,
    required this.joinedAt,
  });
}
