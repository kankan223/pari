import 'academy_module.dart';

/// The cross-pillar sources a study group can link (Task 9.6 — Cross-Pillar
/// Study Group Matching).
///
/// A study group anchors on an Academy module and links related topics from
/// the OTHER pillars (Ledger civic topics, War Room OSINT/legal topics) so
/// learners studying the same module can find each other ACROSS pillars.
/// The pillar is an opaque enum — zero identity by construction.
enum StudyPillar {
  /// The Academy itself (the anchor module / related modules).
  academy,

  /// The Ledger (civic feed topics — public civic content).
  ledger,

  /// The War Room (OSINT / legal advocacy topics).
  warRoom;

  /// Wire name for persistence + sync frames.
  String get wireName => switch (this) {
        StudyPillar.academy => 'academy',
        StudyPillar.ledger => 'ledger',
        StudyPillar.warRoom => 'war_room',
      };

  /// Strict wire decode — unknown pillars throw (a corrupt/forged row can
  /// never masquerade as a real pillar).
  static StudyPillar fromWireName(String raw) => switch (raw) {
        'academy' => StudyPillar.academy,
        'ledger' => StudyPillar.ledger,
        'war_room' => StudyPillar.warRoom,
        _ => throw ArgumentError('Unknown study pillar: $raw'),
      };
}

/// A cross-pillar topic reference (Task 9.6).
///
/// SECURITY CHECKPOINT (Task 9.6): the ref carries ONLY an opaque pillar
/// enum + an OPAQUE topic identifier. For the Academy pillar the topic id is
/// a validated UUID v4 module id; for Ledger/War Room it is an opaque
/// non-PII topic slug (e.g. the ledger category wire name). No names, no
/// phones, no emails, no hashes can be a topic id — the topic id must be
/// either a UUID v4 or a short slug of lowercase letters/digits/underscores.
class StudyTopicRef {
  final StudyPillar pillar;

  /// Opaque non-PII topic id: UUID v4 (academy) or a short slug.
  final String topicId;

  const StudyTopicRef._({required this.pillar, required this.topicId});

  /// Validates the ref: non-empty opaque topic id in one of the two
  /// ALLOWED shapes (UUID v4 or `[a-z0-9_]{1,32}` slug) — zero PII shapes.
  static StudyTopicRef? tryParse({
    required StudyPillar pillar,
    required String topicId,
  }) {
    final raw = topicId.trim();
    if (raw.isEmpty) {
      return null;
    }
    final validUuid = UuidV4.isValid(raw);
    // The slug shape REQUIRES at least one lowercase letter — an all-digit
    // string (e.g. a phone-shaped 10-digit id) is rejected so a PII-shaped
    // topic id can never be a valid ref (SECURITY CHECKPOINT 9.6).
    final validSlug = RegExp(r'^(?=.*[a-z])[a-z0-9_]{1,32}$').hasMatch(raw);
    if (!validUuid && !validSlug) {
      return null;
    }
    return StudyTopicRef._(pillar: pillar, topicId: raw);
  }

  /// Parses via [tryParse], throwing [ArgumentError] on malformed input.
  static StudyTopicRef parse({
    required StudyPillar pillar,
    required String topicId,
  }) {
    final ref = tryParse(pillar: pillar, topicId: topicId);
    if (ref == null) {
      throw ArgumentError('Invalid study topic ref (pillar/topicId '
          'malformed)');
    }
    return ref;
  }

  @override
  bool operator ==(Object other) =>
      other is StudyTopicRef &&
      other.pillar == pillar &&
      other.topicId == topicId;

  @override
  int get hashCode => Object.hash(pillar, topicId);
}

/// A cross-pillar study group (Task 9.6 — Cross-Pillar Study Group
/// Matching).
///
/// SECURITY CHECKPOINT (Task 9.6): the group carries ONLY a validated UUID
/// v4 [groupId], the anchor Academy module's UUID v4 [moduleId], a PUBLIC
/// title, a locale tag, the coarse civic [pinCode] scope (the pin-code-based
/// matching signal — the SAME coarse signal the Ledger feed uses), a list of
/// cross-pillar [topics], a member [capacity] and a participant count. Zero
/// identity, zero phone, zero handle, zero hash fields — participants are
/// identified only by the blinded [StudyGroupHandle] (`SG-####`).
class StudyGroup {
  /// The group's validated UUID v4 id (doubles as the sync idempotency key).
  final String groupId;

  /// The anchor Academy module's validated UUID v4 id.
  final String moduleId;

  /// Public group title (community content, not identity).
  final String title;

  /// ISO 639-1 locale tag (optionally with region).
  final String locale;

  /// The coarse civic scope used for pin-code-based learner matching
  /// (6-digit Indian PIN, e.g. `800001`).
  final String pinCode;

  /// Cross-pillar topic references (Academy modules + Ledger/War Room
  /// topics) — the matching surface.
  final List<StudyTopicRef> topics;

  /// Maximum participant count (>= 2).
  final int capacity;

  /// Current participant count (>= 1, <= capacity).
  final int participantCount;

  /// Group creation timestamp (UTC).
  final DateTime createdAt;

  const StudyGroup._({
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

  /// Validates every field, returning a [StudyGroup] or null when malformed
  /// (bad UUID v4 ids / empty title / bad locale / bad pin / empty topics /
  /// capacity < 2 / counts out of bounds).
  static StudyGroup? tryParse({
    required String groupId,
    required String moduleId,
    required String title,
    required String locale,
    required String pinCode,
    required List<StudyTopicRef> topics,
    required int capacity,
    required int participantCount,
    required DateTime createdAt,
  }) {
    if (!UuidV4.isValid(groupId) ||
        !UuidV4.isValid(moduleId) ||
        title.trim().isEmpty ||
        !LocaleTag.isValid(locale) ||
        !StudyPinCode.isValid(pinCode) ||
        topics.isEmpty ||
        capacity < 2 ||
        participantCount < 1 ||
        participantCount > capacity) {
      return null;
    }
    return StudyGroup._(
      groupId: groupId,
      moduleId: moduleId,
      title: title.trim(),
      locale: locale,
      pinCode: pinCode,
      topics: List.unmodifiable(topics),
      capacity: capacity,
      participantCount: participantCount,
      createdAt: createdAt,
    );
  }

  /// Parses via [tryParse], throwing [ArgumentError] on malformed input.
  static StudyGroup parse({
    required String groupId,
    required String moduleId,
    required String title,
    required String locale,
    required String pinCode,
    required List<StudyTopicRef> topics,
    required int capacity,
    required int participantCount,
    required DateTime createdAt,
  }) {
    final group = tryParse(
      groupId: groupId,
      moduleId: moduleId,
      title: title,
      locale: locale,
      pinCode: pinCode,
      topics: topics,
      capacity: capacity,
      participantCount: participantCount,
      createdAt: createdAt,
    );
    if (group == null) {
      throw ArgumentError('Invalid study group (one or more fields '
          'malformed)');
    }
    return group;
  }

  /// Whether the group still has room for one more participant.
  bool get hasCapacity => participantCount < capacity;

  @override
  bool operator ==(Object other) =>
      other is StudyGroup &&
      other.groupId == groupId &&
      other.moduleId == moduleId &&
      other.title == title &&
      other.locale == locale &&
      other.pinCode == pinCode &&
      _listEquals(other.topics, topics) &&
      other.capacity == capacity &&
      other.participantCount == participantCount &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(groupId, moduleId, title, locale, pinCode,
      Object.hashAll(topics), capacity, participantCount, createdAt);

  static bool _listEquals(List<StudyTopicRef> a, List<StudyTopicRef> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// A study group participant (Task 9.6).
///
/// SECURITY CHECKPOINT (Task 9.6): the participant is identified ONLY by
/// the deterministic blinded [StudyGroupHandle] (`SG-####`, derived from
/// the anchor module id) — never a name, phone, email, blind hash or device
/// id. The member row is the local device's own membership (offline-first —
/// the local membership is written before anything syncs).
class StudyGroupMember {
  /// The member row's validated UUID v4 id (doubles as the sync idempotency
  /// key).
  final String memberId;

  /// The parent group's validated UUID v4 id.
  final String groupId;

  /// The blinded deterministic participant handle (`SG-####`).
  final String memberHandle;

  /// True when this member is the group's initiator.
  final bool isInitiator;

  /// Join timestamp (UTC).
  final DateTime joinedAt;

  const StudyGroupMember._({
    required this.memberId,
    required this.groupId,
    required this.memberHandle,
    required this.isInitiator,
    required this.joinedAt,
  });

  /// Validates every field, returning a [StudyGroupMember] or null when
  /// malformed (bad UUID v4 ids / malformed SG handle).
  static StudyGroupMember? tryParse({
    required String memberId,
    required String groupId,
    required String memberHandle,
    required bool isInitiator,
    required DateTime joinedAt,
  }) {
    if (!UuidV4.isValid(memberId) ||
        !UuidV4.isValid(groupId) ||
        !StudyGroupHandle.isValid(memberHandle)) {
      return null;
    }
    return StudyGroupMember._(
      memberId: memberId,
      groupId: groupId,
      memberHandle: memberHandle,
      isInitiator: isInitiator,
      joinedAt: joinedAt,
    );
  }

  /// Parses via [tryParse], throwing [ArgumentError] on malformed input.
  static StudyGroupMember parse({
    required String memberId,
    required String groupId,
    required String memberHandle,
    required bool isInitiator,
    required DateTime joinedAt,
  }) {
    final member = tryParse(
      memberId: memberId,
      groupId: groupId,
      memberHandle: memberHandle,
      isInitiator: isInitiator,
      joinedAt: joinedAt,
    );
    if (member == null) {
      throw ArgumentError('Invalid study group member (one or more fields '
          'malformed)');
    }
    return member;
  }
}

/// Attributed-but-pseudonymous study group participation (PRD §9.6).
///
/// Every participant is identified by a DETERMINISTIC per-module handle
/// (`SG-` + 4 hex chars from the anchor module id, FNV-1a) — the same module
/// always yields the same handle, so a learner's study-group presence is
/// attributable across groups WITHOUT any identity (mirrors the `SA-####`
/// sandbox authorship). Zero names, phones, hashes or device ids can ever be
/// a participant handle.
abstract final class StudyGroupHandle {
  static final RegExp _pattern = RegExp(r'^SG-[0-9a-f]{4}$');

  static bool isValid(String raw) => _pattern.hasMatch(raw);

  /// The deterministic handle for the anchor [moduleId] (FNV-1a 32-bit →
  /// 4 hex) — the SAME derivation as [SandboxAuthorHandle] so a learner is
  /// consistent across the Academy's community surfaces.
  static String forModule(String moduleId) {
    var hash = 0x811c9dc5;
    for (final unit in moduleId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final suffix = (hash & 0xFFFF).toRadixString(16).padLeft(4, '0');
    return 'SG-$suffix';
  }
}

/// A deterministic match between a learner's study interests and a study
/// group (Task 9.6 — Cross-Pillar Study Group Matching).
///
/// Carries the matched group + the deterministic [score] + the matched topic
/// refs — a non-PII summary safe for the UI (blinded handles only, no
/// identity, no payload).
class StudyGroupMatch {
  final StudyGroup group;
  final int score;

  /// The candidate's topics that matched the learner's interests.
  final List<StudyTopicRef> matchedTopics;

  const StudyGroupMatch({
    required this.group,
    required this.score,
    required this.matchedTopics,
  });
}

/// A learner's matching profile (Task 9.6).
///
/// SECURITY CHECKPOINT (Task 9.6): the profile carries ONLY the coarse civic
/// [pinCode] scope, a locale tag and a list of cross-pillar topic interests
/// (opaque refs) — zero identity, zero PII. The profile never leaves the
/// device unsealed (matching runs locally against the local group snapshot).
class StudyGroupInterest {
  final String pinCode;
  final String locale;

  /// The topics the learner is interested in (cross-pillar opaque refs).
  final List<StudyTopicRef> topics;

  const StudyGroupInterest({
    required this.pinCode,
    required this.locale,
    required this.topics,
  });
}

/// Pure deterministic cross-pillar study group matching (Task 9.6 —
/// MASTER_PLAN §9.6 pin-code-based learner matching).
///
/// Score rules (deterministic, no randomness, no wall-clock):
///   +5  for the anchor module id matching the interest's topics,
///   +3  per ADDITIONAL shared topic ref (Ledger/War Room cross-pillar),
///   +4  for an exact pin-code match (same coarse civic scope),
///   +2  for the same pin district (first 2 digits),
///   +1  for the same pin region (first digit),
///   +2  for a locale match.
/// Full groups (participantCount == capacity) are EXCLUDED from the results
/// (capacity is a hard filter, not a score). Ties are broken deterministically
/// by groupId ascending — every device converges on the identical ranking.
abstract final class StudyGroupMatcher {
  /// Ranks [candidates] against [interest], best match first.
  ///
  /// The anchor module is matched when any interest topic has the Academy
  /// pillar (its topic id is the module id). Deterministic: equal scores are
  /// ordered by groupId ascending.
  static List<StudyGroupMatch> match({
    required StudyGroupInterest interest,
    required List<StudyGroup> candidates,
  }) {
    final results = <StudyGroupMatch>[];
    for (final group in candidates) {
      if (!group.hasCapacity) {
        continue; // full — hard filter.
      }
      var score = 0;
      final matched = <StudyTopicRef>[];
      for (final topic in interest.topics) {
        if (group.topics.contains(topic)) {
          matched.add(topic);
          score += topic.pillar == StudyPillar.academy &&
                  topic.topicId == group.moduleId
              ? 5 // anchor module match.
              : 3; // cross-pillar topic match.
        }
      }
      if (interest.locale == group.locale) {
        score += 2;
      }
      score += _pinScore(interest.pinCode, group.pinCode);
      if (score > 0) {
        results.add(StudyGroupMatch(
          group: group,
          score: score,
          matchedTopics: matched,
        ));
      }
    }
    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return a.group.groupId.compareTo(b.group.groupId);
    });
    return results;
  }

  /// Deterministic pin-code proximity: exact +4, same district (first 2
  /// digits) +2, same region (first digit) +1, else 0.
  static int _pinScore(String learnerPin, String groupPin) {
    if (learnerPin == groupPin) {
      return 4;
    }
    if (learnerPin.length >= 2 &&
        groupPin.length >= 2 &&
        learnerPin.substring(0, 2) == groupPin.substring(0, 2)) {
      return 2;
    }
    if (learnerPin.isNotEmpty &&
        groupPin.isNotEmpty &&
        learnerPin[0] == groupPin[0]) {
      return 1;
    }
    return 0;
  }
}

/// Strict 6-digit Indian PIN code shape (the coarse civic matching scope —
/// the SAME coarse signal the Ledger feed uses; never a precise location).
abstract final class StudyPinCode {
  static final RegExp _pattern = RegExp(r'^\d{6}$');

  static bool isValid(String raw) => _pattern.hasMatch(raw);
}

/// Cross-pillar study group persistence boundary (port, Task 9.6).
///
/// The production implementation is backed by the encrypted SQLCipher
/// database (`study_groups` + `study_group_members`, schema v13) and is
/// OFFLINE-FIRST: the local rows are written before anything else; the
/// sealed sync enqueue (QueueStudyGroupSink) wraps the same port. All ids
/// are validated UUID v4; participant handles are `SG-####` only.
abstract class StudyGroupRepository {
  /// Every group, newest-created first (optionally scoped to [moduleId]).
  Future<List<StudyGroup>> listGroups({String? moduleId});

  /// The group with [groupId], or null when absent.
  Future<StudyGroup?> getGroup(String groupId);

  /// The local member rows for [groupId] (the local device's memberships).
  Future<List<StudyGroupMember>> listMembers(String groupId);

  /// Creates a study group and records the initiator membership.
  ///
  /// [initiatorHandle] is the blinded `SG-####` handle of the creator. The
  /// group starts with participantCount 1 (the initiator). Returns the
  /// created group.
  Future<StudyGroup> createGroup({
    required String moduleId,
    required String title,
    required String locale,
    required String pinCode,
    required List<StudyTopicRef> topics,
    required int capacity,
    required String initiatorHandle,
  });

  /// Joins [groupId] as [memberHandle] (blinded `SG-####`).
  ///
  /// Throws when the group is absent or full. Returns the updated group.
  Future<StudyGroup> joinGroup({
    required String groupId,
    required String memberHandle,
  });
}
