import 'dart:convert';

import 'package:civic_commons/academy/domain/study_group.dart';
import 'package:civic_commons/academy/domain/study_group_wire_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

StudyGroupWireFrame _frame({
  bool isJoin = false,
  bool isInitiator = false,
}) =>
    StudyGroupWireFrame(
      groupId: 'b0e1c2d3-4a5b-4c6d-8e7f-1a2b3c4d5e6f',
      moduleId: _m1,
      title: 'Civic Rights Study Circle',
      locale: 'en',
      pinCode: '800001',
      topics: [
        StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: _m1),
        StudyTopicRef.parse(pillar: StudyPillar.ledger, topicId: 'civics'),
      ],
      capacity: 6,
      memberHandle: StudyGroupHandle.forModule(_m1),
      isInitiator: isInitiator,
      isJoin: isJoin,
      createdAtMs: 1786924800000,
    );

void main() {
  group('StudyGroupWireFrame codec (Task 9.6)', () {
    test('create frame round-trips through encode/decode', () {
      final frame = _frame(isInitiator: true);
      final bytes = encodeStudyGroupFrame(frame);
      final decoded = decodeStudyGroupFrame(bytes);

      expect(decoded.groupId, frame.groupId);
      expect(decoded.moduleId, _m1);
      expect(decoded.title, 'Civic Rights Study Circle');
      expect(decoded.locale, 'en');
      expect(decoded.pinCode, '800001');
      expect(decoded.topics, hasLength(2));
      expect(decoded.topics[0].pillar, StudyPillar.academy);
      expect(decoded.topics[1].pillar, StudyPillar.ledger);
      expect(decoded.capacity, 6);
      expect(decoded.memberHandle, StudyGroupHandle.forModule(_m1));
      expect(decoded.isInitiator, isTrue);
      expect(decoded.isJoin, isFalse);
      expect(decoded.createdAtMs, 1786924800000);
    });

    test('join frame round-trips', () {
      final frame = _frame(isJoin: true);
      final decoded = decodeStudyGroupFrame(encodeStudyGroupFrame(frame));
      expect(decoded.isJoin, isTrue);
      expect(decoded.isInitiator, isFalse);
    });

    test('frame JSON uses canonical snake_case keys', () {
      final json = jsonDecode(
          utf8.decode(encodeStudyGroupFrame(_frame(isInitiator: true))));
      expect(json, isA<Map<String, Object?>>());
      final map = json as Map<String, Object?>;
      expect(map['v'], 1);
      expect(map['group_id'], 'b0e1c2d3-4a5b-4c6d-8e7f-1a2b3c4d5e6f');
      expect(map['pin_code'], '800001');
      expect(map['member_handle'], StudyGroupHandle.forModule(_m1));
      expect(map.containsKey('created_at_ms'), isTrue);
      // Zero identity fields — the frame declares NO phone/name/hash keys.
      for (final forbidden in ['phone', 'email', 'name', 'hash', 'device']) {
        expect(map.keys.any((k) => k.contains(forbidden)), isFalse,
            reason: 'frame must never carry a $forbidden field');
      }
    });

    test('decode rejects unknown versions', () {
      final json = _frame(isInitiator: true).toJson();
      json['v'] = 2;
      expect(
        () => StudyGroupWireFrame.fromJson(json),
        throwsArgumentError,
      );
    });

    test('decode rejects non-UUID ids', () {
      final json = _frame().toJson();
      json['group_id'] = 'not-a-uuid';
      expect(() => StudyGroupWireFrame.fromJson(json), throwsArgumentError);
    });

    test('decode rejects malformed handles / pins', () {
      final badHandle = _frame().toJson();
      badHandle['member_handle'] = 'SX-1a2b';
      expect(
        () => StudyGroupWireFrame.fromJson(badHandle),
        throwsArgumentError,
      );

      final badPin = _frame().toJson();
      badPin['pin_code'] = '12345';
      expect(() => StudyGroupWireFrame.fromJson(badPin), throwsArgumentError);
    });

    test('decode rejects malformed/empty topics', () {
      final badTopic = _frame().toJson();
      badTopic['topics'] = ['ledger:civics', 'bogus'];
      expect(
        () => StudyGroupWireFrame.fromJson(badTopic),
        throwsArgumentError,
      );

      final empty = _frame().toJson();
      empty['topics'] = <String>[];
      expect(() => StudyGroupWireFrame.fromJson(empty), throwsArgumentError);
    });

    test('decode rejects non-object bytes', () {
      expect(
        () => decodeStudyGroupFrame(utf8.encode('[1,2,3]')),
        throwsFormatException,
      );
    });
  });
}
