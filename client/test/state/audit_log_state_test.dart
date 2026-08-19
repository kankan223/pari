import 'package:civic_commons/state/domain/audit_log_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditLogState', () {
    test('default state is idle with empty records', () {
      const state = AuditLogState();
      expect(state.phase, AuditLogPhase.idle);
      expect(state.records, isEmpty);
      expect(state.integrityValid, true);
      expect(state.recordCount, 0);
      expect(state.errorMessage, isNull);
    });

    test('ready state carries records and count', () {
      const state = AuditLogState(
        phase: AuditLogPhase.ready,
        recordCount: 5,
        integrityValid: true,
      );
      expect(state.phase, AuditLogPhase.ready);
      expect(state.recordCount, 5);
      expect(state.integrityValid, true);
    });

    test('error state carries error message', () {
      const state = AuditLogState(
        phase: AuditLogPhase.error,
        errorMessage: 'Something went wrong',
      );
      expect(state.phase, AuditLogPhase.error);
      expect(state.errorMessage, 'Something went wrong');
    });

    test('integrityValid can be false', () {
      const state = AuditLogState(
        phase: AuditLogPhase.ready,
        integrityValid: false,
      );
      expect(state.integrityValid, false);
    });

    test('loading phase is set during data loading', () {
      const state = AuditLogState(phase: AuditLogPhase.loading);
      expect(state.phase, AuditLogPhase.loading);
    });
  });
}
