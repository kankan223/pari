import 'package:civic_commons/transparency/domain/transparency_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransparencyAction', () {
    test('has exactly six actions', () {
      expect(TransparencyAction.values.length, 6);
    });

    test('wire round-trip for every action', () {
      for (final action in TransparencyAction.values) {
        final decoded = TransparencyAction.fromWireName(action.name);
        expect(decoded, action);
      }
    });

    test('labels are non-empty', () {
      for (final action in TransparencyAction.values) {
        expect(action.label.isNotEmpty, true);
        expect(action.shortLabel.isNotEmpty, true);
      }
    });

    test('unknown wire name throws FormatException', () {
      expect(
        () => TransparencyAction.fromWireName('unknown_action'),
        throwsFormatException,
      );
    });

    test('empty wire name throws FormatException', () {
      expect(
        () => TransparencyAction.fromWireName(''),
        throwsFormatException,
      );
    });
  });
}
