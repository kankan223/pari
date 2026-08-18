import 'package:civic_commons/state/domain/transparency_log_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransparencyLogState', () {
    test('default state is idle with empty list', () {
      const state = TransparencyLogState();
      expect(state.phase, TransparencyLogPhase.idle);
      expect(state.records, isEmpty);
      expect(state.integrityValid, true);
      expect(state.recordCount, 0);
    });

    test('ready state carries records and integrity', () {
      const state = TransparencyLogState(
        phase: TransparencyLogPhase.ready,
        records: [],
        integrityValid: true,
        recordCount: 5,
      );

      expect(state.phase, TransparencyLogPhase.ready);
      expect(state.integrityValid, true);
      expect(state.recordCount, 5);
    });

    test('error state carries errorMessage', () {
      const state = TransparencyLogState(
        phase: TransparencyLogPhase.error,
        errorMessage: 'Unable to load transparency log',
      );

      expect(state.phase, TransparencyLogPhase.error);
      expect(state.errorMessage, 'Unable to load transparency log');
      expect(state.records, isEmpty);
    });

    test('integrityInvalid state', () {
      const state = TransparencyLogState(
        phase: TransparencyLogPhase.ready,
        integrityValid: false,
        recordCount: 3,
      );

      expect(state.integrityValid, false);
      expect(state.recordCount, 3);
    });
  });
}
