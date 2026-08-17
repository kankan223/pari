import 'package:civic_commons/academy/domain/study_group.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const _m2 = '9d2f1b7a-6c3e-4a5b-8f1d-2c9e4a7b6f10';

StudyGroup _group({
  String groupId = 'b0e1c2d3-4a5b-4c6d-8e7f-1a2b3c4d5e6f',
  String moduleId = _m1,
  String title = 'Civic Rights Study Circle',
  String locale = 'en',
  String pinCode = '800001',
  List<StudyTopicRef>? topics,
  int capacity = 6,
  int participantCount = 1,
}) =>
    StudyGroup.parse(
      groupId: groupId,
      moduleId: moduleId,
      title: title,
      locale: locale,
      pinCode: pinCode,
      topics: topics ??
          [
            StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: moduleId),
            StudyTopicRef.parse(pillar: StudyPillar.ledger, topicId: 'civics'),
          ],
      capacity: capacity,
      participantCount: participantCount,
      createdAt: DateTime.utc(2026, 8, 17),
    );

StudyGroup? _groupOrNull({
  String groupId = 'b0e1c2d3-4a5b-4c6d-8e7f-1a2b3c4d5e6f',
  String moduleId = _m1,
  String title = 'Civic Rights Study Circle',
  String locale = 'en',
  String pinCode = '800001',
  List<StudyTopicRef>? topics,
  int capacity = 6,
  int participantCount = 1,
}) {
  // The DEFAULT topics derive from the FIXED _m1 (never the passed
  // moduleId) so a malformed moduleId reaches StudyGroup.tryParse (which
  // returns null) instead of throwing inside the topic builder.
  final refs = topics ??
      [
        StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: _m1),
        StudyTopicRef.parse(pillar: StudyPillar.ledger, topicId: 'civics'),
      ];
  return StudyGroup.tryParse(
    groupId: groupId,
    moduleId: moduleId,
    title: title,
    locale: locale,
    pinCode: pinCode,
    topics: refs,
    capacity: capacity,
    participantCount: participantCount,
    createdAt: DateTime.utc(2026, 8, 17),
  );
}

void main() {
  group('StudyTopicRef - validation', () {
    test('accepts a UUID v4 topic id (academy pillar)', () {
      final ref =
          StudyTopicRef.tryParse(pillar: StudyPillar.academy, topicId: _m1);
      expect(ref, isNotNull);
      expect(ref!.pillar, StudyPillar.academy);
      expect(ref.topicId, _m1);
    });

    test('accepts a short lowercase slug topic id (ledger/war room)', () {
      expect(
        StudyTopicRef.tryParse(pillar: StudyPillar.ledger, topicId: 'civics'),
        isNotNull,
      );
      expect(
        StudyTopicRef.tryParse(pillar: StudyPillar.warRoom, topicId: 'osint'),
        isNotNull,
      );
    });

    test('rejects empty / PII-shaped / mixed-case topic ids', () {
      expect(
        StudyTopicRef.tryParse(pillar: StudyPillar.ledger, topicId: ''),
        isNull,
      );
      expect(
        StudyTopicRef.tryParse(pillar: StudyPillar.ledger, topicId: 'Civics'),
        isNull, // mixed case — slug shape is strict lowercase.
      );
      expect(
        StudyTopicRef.tryParse(
            pillar: StudyPillar.ledger, topicId: '8000012345'),
        isNull, // phone-shaped numeric id — rejected.
      );
      expect(
        StudyTopicRef.tryParse(
            pillar: StudyPillar.ledger,
            topicId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                'aaaaaaaaaaaaaaaaaaaaaaaa'),
        isNull, // over 32 chars.
      );
    });

    test('parse throws ArgumentError on malformed input', () {
      expect(
        () => StudyTopicRef.parse(pillar: StudyPillar.ledger, topicId: ''),
        throwsArgumentError,
      );
    });

    test('pillar wire names round-trip strictly', () {
      for (final p in StudyPillar.values) {
        expect(StudyPillar.fromWireName(p.wireName), p);
      }
      expect(() => StudyPillar.fromWireName('bogus'), throwsArgumentError);
    });
  });

  group('StudyGroup - validation', () {
    test('valid group parses and enforces capacity bounds', () {
      final g = _group();
      expect(g.groupId, 'b0e1c2d3-4a5b-4c6d-8e7f-1a2b3c4d5e6f');
      expect(g.hasCapacity, isTrue);
      expect(
        _group(capacity: 2, participantCount: 2).hasCapacity,
        isFalse,
      );
    });

    test('rejects malformed fields', () {
      expect(
        _groupOrNull(groupId: 'not-a-uuid'),
        isNull,
      );
      expect(_groupOrNull(moduleId: 'not-a-uuid'), isNull);
      expect(_groupOrNull(title: '  '), isNull);
      expect(_groupOrNull(locale: 'invalid locale!'), isNull);
      expect(_groupOrNull(pinCode: '12345'), isNull);
      expect(_groupOrNull(capacity: 1), isNull);
      expect(
        _groupOrNull(participantCount: 0),
        isNull,
      );
      expect(
        _groupOrNull(participantCount: 7, capacity: 6),
        isNull,
      );
      expect(_groupOrNull(topics: const []), isNull);
    });

    test('parse throws ArgumentError on malformed input', () {
      expect(
        () => _group(groupId: 'not-a-uuid'),
        throwsArgumentError,
      );
    });

    test('value equality compares every field', () {
      expect(_group(), _group());
      expect(_group(title: 'Other'), isNot(_group()));
    });
  });

  group('StudyGroupHandle - deterministic blinding', () {
    test('SG-#### shape and determinism', () {
      final h1 = StudyGroupHandle.forModule(_m1);
      final h2 = StudyGroupHandle.forModule(_m1);
      expect(h1, h2, reason: 'same module → same handle (deterministic)');
      expect(RegExp(r'^SG-[0-9a-f]{4}$').hasMatch(h1), isTrue);
      expect(StudyGroupHandle.isValid(h1), isTrue);
      expect(StudyGroupHandle.isValid('SA-1a2b'), isFalse);
      expect(StudyGroupHandle.isValid('SG-12345'), isFalse);
    });

    test('different modules yield different handles', () {
      expect(
        StudyGroupHandle.forModule(_m1),
        isNot(StudyGroupHandle.forModule(_m2)),
      );
    });
  });

  group('StudyGroupMember - validation', () {
    test('valid member parses', () {
      final m = StudyGroupMember.parse(
        memberId: 'c0f2a3b4-5c6d-4e7f-9a8b-3c4d5e6f7a8b',
        groupId: 'b0e1c2d3-4a5b-4c6d-8e7f-1a2b3c4d5e6f',
        memberHandle: StudyGroupHandle.forModule(_m1),
        isInitiator: true,
        joinedAt: DateTime.utc(2026, 8, 17),
      );
      expect(m.memberHandle, startsWith('SG-'));
      expect(m.isInitiator, isTrue);
    });

    test('rejects malformed members', () {
      expect(
        StudyGroupMember.tryParse(
          memberId: 'not-a-uuid',
          groupId: 'b0e1c2d3-4a5b-4c6d-8e7f-1a2b3c4d5e6f',
          memberHandle: 'SG-1a2b',
          isInitiator: false,
          joinedAt: DateTime.utc(2026, 8, 17),
        ),
        isNull,
      );
      expect(
        StudyGroupMember.tryParse(
          memberId: 'c0f2a3b4-5c6d-4e7f-9a8b-3c4d5e6f7a8b',
          groupId: 'b0e1c2d3-4a5b-4c6d-8e7f-1a2b3c4d5e6f',
          memberHandle: 'SX-1a2b', // malformed handle.
          isInitiator: false,
          joinedAt: DateTime.utc(2026, 8, 17),
        ),
        isNull,
      );
    });
  });

  group('StudyGroupMatcher - deterministic pin-code matching', () {
    StudyGroupInterest interest({
      String pinCode = '800001',
      String locale = 'en',
      List<StudyTopicRef>? topics,
    }) =>
        StudyGroupInterest(
          pinCode: pinCode,
          locale: locale,
          topics: topics ??
              [
                StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: _m1),
              ],
        );

    test('anchor module match scores highest', () {
      final results = StudyGroupMatcher.match(
        interest: interest(),
        candidates: [_group()],
      );
      expect(results, hasLength(1));
      expect(results.single.score, greaterThan(0));
    });

    test('exact pin beats same-district beats same-region', () {
      final exact = StudyGroupMatcher.match(
        interest: interest(pinCode: '800001'),
        candidates: [
          _group(
              pinCode: '800001',
              groupId: 'aaaaaaa1-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
          _group(
              pinCode: '800002',
              groupId: 'bbbbbbb1-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
          _group(
              pinCode: '810001',
              groupId: 'ccccccc1-cccc-4ccc-8ccc-cccccccccccc'),
        ],
      );
      // All three share the anchor module (+5) + locale (+2), so only pin
      // proximity differs (+4 exact / +2 district / +1 region).
      expect(resultsScore(exact), [11, 9, 8]);
    });

    test('full groups are excluded (hard filter)', () {
      final results = StudyGroupMatcher.match(
        interest: interest(),
        candidates: [
          _group(capacity: 2, participantCount: 2),
          _group(groupId: 'ddddddd1-dddd-4ddd-8ddd-dddddddddddd'),
        ],
      );
      expect(results, hasLength(1));
      expect(
          results.single.group.groupId, 'ddddddd1-dddd-4ddd-8ddd-dddddddddddd');
    });

    test('locale match adds points deterministically', () {
      final hi = StudyGroupMatcher.match(
        interest: interest(locale: 'hi'),
        candidates: [
          _group(locale: 'hi', groupId: 'eeeeeee1-eeee-4eee-8eee-eeeeeeeeeeee'),
          _group(locale: 'en', groupId: 'fffffff1-ffff-4fff-8fff-ffffffffffff'),
        ],
      );
      // Both share the anchor (+5) + exact pin (+4); the locale match adds
      // +2 for the hi group — 11 vs 9.
      expect(resultsScore(hi), [11, 9]);
    });

    test('cross-pillar topic refs add points', () {
      final results = StudyGroupMatcher.match(
        interest: interest(topics: [
          StudyTopicRef.parse(pillar: StudyPillar.academy, topicId: _m1),
          StudyTopicRef.parse(pillar: StudyPillar.ledger, topicId: 'civics'),
        ]),
        candidates: [_group()],
      );
      expect(results.single.matchedTopics, hasLength(2));
    });

    test('equal scores break deterministically by groupId ascending', () {
      // Two groups identical in every scored dimension but their ids.
      final a = _group(
          groupId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', pinCode: '800001');
      final b = _group(
          groupId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', pinCode: '800001');
      final results = StudyGroupMatcher.match(
        interest: interest(),
        candidates: [b, a],
      );
      expect(results, hasLength(2));
      expect(results[0].group.groupId, a.groupId,
          reason: 'tie → lower groupId first (deterministic)');
      // Repeated invocation is identical — no randomness.
      final again = StudyGroupMatcher.match(
        interest: interest(),
        candidates: [b, a],
      );
      expect(
        again.map((m) => m.group.groupId).toList(),
        results.map((m) => m.group.groupId).toList(),
      );
    });

    test('irrelevant candidates score zero and are dropped', () {
      final results = StudyGroupMatcher.match(
        interest: interest(locale: 'hi', pinCode: '110001'),
        candidates: [
          _group(
              locale: 'en',
              pinCode: '700001',
              // Explicitly NOT the interest module — a fully irrelevant
              // topic set so nothing can match.
              topics: [
                StudyTopicRef.parse(
                    pillar: StudyPillar.warRoom, topicId: 'osint'),
              ],
              groupId: '99999991-9999-4999-8999-999999999999'),
        ],
      );
      expect(results, isEmpty);
    });
  });
}

List<int> resultsScore(List<StudyGroupMatch> results) =>
    results.map((m) => m.score).toList();
