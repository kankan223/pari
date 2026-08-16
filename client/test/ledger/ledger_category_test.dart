import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LedgerCategory', () {
    test('has the 5 PRD categories', () {
      expect(
        LedgerCategory.values,
        [
          LedgerCategory.civicInfrastructure,
          LedgerCategory.studentRights,
          LedgerCategory.consumerWatch,
          LedgerCategory.satireAndCulture,
          LedgerCategory.breakingLocal,
        ],
      );
    });

    test('labels match DESIGN.md §4.4 chip texts', () {
      expect(LedgerCategory.civicInfrastructure.label, '#CIVIC INFRA');
      expect(LedgerCategory.studentRights.label, '#STUDENTS');
      expect(LedgerCategory.consumerWatch.label, '#CONSUMER');
      expect(LedgerCategory.satireAndCulture.label, '#SATIRE');
      expect(LedgerCategory.breakingLocal.label, '#BREAKING');
    });

    test('full names are the compose dropdown labels', () {
      expect(
          LedgerCategory.civicInfrastructure.fullName, 'Civic Infrastructure');
      expect(LedgerCategory.studentRights.fullName, 'Student Rights');
      expect(LedgerCategory.consumerWatch.fullName, 'Consumer Watch');
      expect(LedgerCategory.satireAndCulture.fullName, 'Satire & Culture');
      expect(LedgerCategory.breakingLocal.fullName, 'Breaking Local');
    });

    test('wire names round-trip', () {
      for (final category in LedgerCategory.values) {
        expect(
          LedgerCategory.fromWireName(category.wireName),
          category,
        );
      }
    });

    test('fromWireName rejects unknown values (strict bounds)', () {
      expect(
        () => LedgerCategory.fromWireName('memes_extra'),
        throwsArgumentError,
      );
    });
  });
}
