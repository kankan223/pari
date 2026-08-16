import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/ledger/domain/ledger_vote.dart';
import 'package:civic_commons/ledger/domain/ledger_vote_wire_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LedgerVoteWireFrame codec (Task 7.5)', () {
    test('encode -> decode round-trips every field exactly', () {
      for (final direction in [
        LedgerVoteDirection.up,
        LedgerVoteDirection.down,
      ]) {
        final frame = LedgerVoteWireFrame(
          postId: 'post_abc123',
          direction: direction,
        );
        final restored = decodeLedgerVoteFrame(encodeLedgerVoteFrame(frame));
        expect(restored.postId, 'post_abc123');
        expect(restored.direction, direction);
      }
    });

    test('wire frame carries ONLY post id + direction — never identity', () {
      const frame = LedgerVoteWireFrame(
        postId: 'post_abc123',
        direction: LedgerVoteDirection.up,
      );
      final json = frame.toJson();

      expect(json.keys.toSet(), {'v', 'post_id', 'direction'});
      final values = json.values.join(',').toLowerCase();
      expect(values, isNot(contains('hash')));
      expect(values, isNot(contains('phone')));
      expect(values, isNot(contains('author')));
      expect(values, isNot(contains('blind')));
    });

    test('decode rejects an unknown direction (strict bounds)', () {
      final bytes = Uint8List.fromList(utf8.encode(
        jsonEncode({'v': 1, 'post_id': 'p1', 'direction': 'sideways'}),
      ));
      expect(() => decodeLedgerVoteFrame(bytes), throwsArgumentError);
    });

    test('decode rejects an unsupported wire version', () {
      final bytes = Uint8List.fromList(utf8.encode(
        jsonEncode({'v': 99, 'post_id': 'p1', 'direction': 'up'}),
      ));
      expect(() => decodeLedgerVoteFrame(bytes), throwsArgumentError);
    });

    test('decode rejects non-object payloads', () {
      final array = Uint8List.fromList(utf8.encode('[1,2]'));
      expect(() => decodeLedgerVoteFrame(array), throwsFormatException);
      final garbage = Uint8List.fromList([0xff, 0xfe]);
      expect(() => decodeLedgerVoteFrame(garbage), throwsFormatException);
    });

    test('encoding is deterministic for identical votes', () {
      const a = LedgerVoteWireFrame(
        postId: 'p1',
        direction: LedgerVoteDirection.down,
      );
      const b = LedgerVoteWireFrame(
        postId: 'p1',
        direction: LedgerVoteDirection.down,
      );
      expect(encodeLedgerVoteFrame(a), equals(encodeLedgerVoteFrame(b)));
    });
  });
}
