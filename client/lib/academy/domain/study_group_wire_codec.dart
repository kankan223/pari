import 'dart:convert';
import 'dart:typed_data';

import 'academy_module.dart';
import 'study_group.dart';

/// A canonical wire frame for a study group mutation (Task 9.6 — Cross-
/// Pillar Study Group Matching).
///
/// SECURITY CONTRACT: the frame carries ONLY the group/module UUID v4 ids,
/// the public title, the locale tag, the coarse civic pin-code scope, the
/// cross-pillar opaque topic refs, a capacity and the blinded `SG-####`
/// initiator/member handle — zero identity, zero PII. It is SEALED by the
/// sync-queue cipher before storage, so the queue never persists this
/// plaintext (MASTER_PLAN §9.6 checkpoint: study group data is sealed before
/// sync). The codec is strict on DECODE (bad UUID v4 ids, unknown versions,
/// malformed handles/pins/topics throw — a corrupt/forged envelope can never
/// masquerade as a real mutation).
class StudyGroupWireFrame {
  final String groupId;
  final String moduleId;
  final String title;
  final String locale;
  final String pinCode;
  final List<StudyTopicRef> topics;
  final int capacity;
  final String memberHandle;
  final bool isInitiator;
  final bool isJoin;
  final int createdAtMs;

  const StudyGroupWireFrame({
    required this.groupId,
    required this.moduleId,
    required this.title,
    required this.locale,
    required this.pinCode,
    required this.topics,
    required this.capacity,
    required this.memberHandle,
    required this.isInitiator,
    required this.isJoin,
    required this.createdAtMs,
  });

  Map<String, Object?> toJson() => {
        'v': 1,
        'group_id': groupId,
        'module_id': moduleId,
        'title': title,
        'locale': locale,
        'pin_code': pinCode,
        'topics':
            topics.map((t) => '${t.pillar.wireName}:${t.topicId}').toList(),
        'capacity': capacity,
        'member_handle': memberHandle,
        'is_initiator': isInitiator ? 1 : 0,
        'is_join': isJoin ? 1 : 0,
        'created_at_ms': createdAtMs,
      };

  static StudyGroupWireFrame fromJson(Map<String, Object?> json) {
    if (json['v'] != 1) {
      throw ArgumentError('Unsupported study group wire version: ${json['v']}');
    }
    final groupId = json['group_id']! as String;
    final moduleId = json['module_id']! as String;
    final memberHandle = json['member_handle']! as String;
    final pinCode = json['pin_code']! as String;
    if (!UuidV4.isValid(groupId) || !UuidV4.isValid(moduleId)) {
      throw ArgumentError('Study group frame carries a non-UUID id');
    }
    if (!StudyGroupHandle.isValid(memberHandle)) {
      throw ArgumentError('Study group frame carries a malformed handle');
    }
    if (!StudyPinCode.isValid(pinCode)) {
      throw ArgumentError('Study group frame carries a malformed pin');
    }
    final topics = <StudyTopicRef>[];
    for (final raw in (json['topics']! as List).cast<String>()) {
      final sep = raw.indexOf(':');
      if (sep <= 0) {
        throw ArgumentError('Study group frame carries a malformed topic');
      }
      final pillar = StudyPillar.fromWireName(raw.substring(0, sep));
      final topic = StudyTopicRef.tryParse(
        pillar: pillar,
        topicId: raw.substring(sep + 1),
      );
      if (topic == null) {
        throw ArgumentError('Study group frame carries a malformed topic');
      }
      topics.add(topic);
    }
    if (topics.isEmpty) {
      throw ArgumentError('Study group frame carries no topics');
    }
    return StudyGroupWireFrame(
      groupId: groupId,
      moduleId: moduleId,
      title: json['title']! as String,
      locale: json['locale']! as String,
      pinCode: pinCode,
      topics: topics,
      capacity: json['capacity']! as int,
      memberHandle: memberHandle,
      isInitiator: (json['is_initiator']! as int) == 1,
      isJoin: (json['is_join']! as int) == 1,
      createdAtMs: json['created_at_ms']! as int,
    );
  }
}

/// Serializes [StudyGroupWireFrame] to the opaque bytes queued for sync
/// (sealed by the queue repository before storage).
Uint8List encodeStudyGroupFrame(StudyGroupWireFrame frame) =>
    Uint8List.fromList(utf8.encode(jsonEncode(frame.toJson())));

/// Strictly decodes queued study group bytes; throws [FormatException] /
/// [ArgumentError] on malformed input or invalid ids/handles/pins/topics.
StudyGroupWireFrame decodeStudyGroupFrame(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Study group frame must be a JSON object');
  }
  return StudyGroupWireFrame.fromJson(decoded);
}
