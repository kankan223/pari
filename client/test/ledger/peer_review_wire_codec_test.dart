import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/ledger/domain/peer_review.dart';
import 'package:civic_commons/ledger/domain/peer_review_wire_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeerReviewWireFrame codec (Task 7.6)', () {
    test('encode -> decode round-trips every field exactly', () {
      for (final decision in PeerReviewDecision.values) {
        final frame = PeerReviewWireFrame(
          postId: 'post_abc123',
          decision: decision,
        );
        final restored = decodePeerReviewFrame(encodePeerReviewFrame(frame));
        expect(restored.postId, 'post_abc123');
        expect(restored.decision, decision);
      }
    });

    test('wire frame carries ONLY post id + decision — never identity', () {
      const frame = PeerReviewWireFrame(
        postId: 'post_abc123',
        decision: PeerReviewDecision.approved,
      );
      final json = frame.toJson();

      expect(json.keys.toSet(), {'v', 'post_id', 'decision'});
      final values = json.values.join(',').toLowerCase();
      expect(values, isNot(contains('hash')));
      expect(values, isNot(contains('phone')));
      expect(values, isNot(contains('author')));
      expect(values, isNot(contains('blind')));
      expect(values, isNot(contains('reviewer')));
    });

    test('wire names are the stable server contract', () {
      expect(PeerReviewDecision.approved.wireName, 'approved');
      expect(PeerReviewDecision.rejected.wireName, 'rejected');
      expect(PeerReviewDecision.flagged.wireName, 'flagged');
      expect(PeerReviewDecision.fromWireName('approved'),
          PeerReviewDecision.approved);
    });

    test('decode rejects an unknown decision (strict bounds)', () {
      final bytes = Uint8List.fromList(utf8.encode(
        jsonEncode({'v': 1, 'post_id': 'p1', 'decision': 'sideways'}),
      ));
      expect(() => decodePeerReviewFrame(bytes), throwsArgumentError);
    });

    test('decode rejects an unsupported wire version', () {
      final bytes = Uint8List.fromList(utf8.encode(
        jsonEncode({'v': 99, 'post_id': 'p1', 'decision': 'approved'}),
      ));
      expect(() => decodePeerReviewFrame(bytes), throwsArgumentError);
    });

    test('decode rejects non-object payloads', () {
      final array = Uint8List.fromList(utf8.encode('[1,2]'));
      expect(() => decodePeerReviewFrame(array), throwsFormatException);
      final garbage = Uint8List.fromList([0xff, 0xfe]);
      expect(() => decodePeerReviewFrame(garbage), throwsFormatException);
    });

    test('encoding is deterministic for identical decisions', () {
      const a = PeerReviewWireFrame(
        postId: 'p1',
        decision: PeerReviewDecision.rejected,
      );
      const b = PeerReviewWireFrame(
        postId: 'p1',
        decision: PeerReviewDecision.rejected,
      );
      expect(encodePeerReviewFrame(a), equals(encodePeerReviewFrame(b)));
    });
  });
}
