import 'package:civic_commons/documentation/domain/adr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.1 — Architecture Decision Records', () {
    group('AdrStatus', () {
      test('has all statuses', () {
        expect(AdrStatus.values.length, 4);
        expect(AdrStatus.values, contains(AdrStatus.proposed));
        expect(AdrStatus.values, contains(AdrStatus.accepted));
        expect(AdrStatus.values, contains(AdrStatus.deprecated));
        expect(AdrStatus.values, contains(AdrStatus.superseded));
      });

      test('label capitalizes first letter', () {
        expect(AdrStatus.proposed.label, 'Proposed');
        expect(AdrStatus.accepted.label, 'Accepted');
        expect(AdrStatus.deprecated.label, 'Deprecated');
        expect(AdrStatus.superseded.label, 'Superseded');
      });
    });

    group('Adr', () {
      test('constructs with required fields', () {
        const adr = Adr(
          id: 'ADR-001',
          title: 'Use SQLCipher for Local Storage',
          status: AdrStatus.accepted,
          date: '2026-01-15',
          context: 'We need encrypted local storage.',
          decision: 'Use SQLCipher with AES-256.',
          consequences: 'All data encrypted at rest.',
        );
        expect(adr.id, 'ADR-001');
        expect(adr.title, 'Use SQLCipher for Local Storage');
        expect(adr.status, AdrStatus.accepted);
        expect(adr.isActive, isTrue);
        expect(adr.isHistorical, isFalse);
      });

      test('isActive for proposed and accepted', () {
        const proposed = Adr(
          id: 'ADR-002',
          title: 'Test',
          status: AdrStatus.proposed,
          date: '2026-01-01',
          context: '',
          decision: '',
          consequences: '',
        );
        const accepted = Adr(
          id: 'ADR-003',
          title: 'Test',
          status: AdrStatus.accepted,
          date: '2026-01-01',
          context: '',
          decision: '',
          consequences: '',
        );
        expect(proposed.isActive, isTrue);
        expect(accepted.isActive, isTrue);
      });

      test('isHistorical for deprecated and superseded', () {
        const deprecated = Adr(
          id: 'ADR-004',
          title: 'Test',
          status: AdrStatus.deprecated,
          date: '2026-01-01',
          context: '',
          decision: '',
          consequences: '',
        );
        const superseded = Adr(
          id: 'ADR-005',
          title: 'Test',
          status: AdrStatus.superseded,
          date: '2026-01-01',
          context: '',
          decision: '',
          consequences: '',
        );
        expect(deprecated.isHistorical, isTrue);
        expect(superseded.isHistorical, isTrue);
      });

      test('equality by id', () {
        const a = Adr(
          id: 'ADR-001',
          title: 'Title A',
          status: AdrStatus.accepted,
          date: '2026-01-01',
          context: '',
          decision: '',
          consequences: '',
        );
        const b = Adr(
          id: 'ADR-001',
          title: 'Title B',
          status: AdrStatus.proposed,
          date: '2026-02-01',
          context: '',
          decision: '',
          consequences: '',
        );
        const c = Adr(
          id: 'ADR-002',
          title: 'Title A',
          status: AdrStatus.accepted,
          date: '2026-01-01',
          context: '',
          decision: '',
          consequences: '',
        );
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('AdrRegistry', () {
      test('empty registry has zero count', () {
        final registry = AdrRegistry.empty();
        expect(registry.count, 0);
        expect(registry.all, isEmpty);
      });

      test('withAdr adds an ADR', () {
        const adr = Adr(
          id: 'ADR-001',
          title: 'Test',
          status: AdrStatus.accepted,
          date: '2026-01-01',
          context: '',
          decision: '',
          consequences: '',
        );
        final registry = AdrRegistry.empty().withAdr(adr);
        expect(registry.count, 1);
        expect(registry.getById('ADR-001'), equals(adr));
      });

      test('withoutAdr removes an ADR', () {
        const adr = Adr(
          id: 'ADR-001',
          title: 'Test',
          status: AdrStatus.accepted,
          date: '2026-01-01',
          context: '',
          decision: '',
          consequences: '',
        );
        final registry = AdrRegistry.empty().withAdr(adr).withoutAdr('ADR-001');
        expect(registry.count, 0);
        expect(registry.getById('ADR-001'), isNull);
      });

      test('accepted returns only accepted ADRs', () {
        final registry = AdrRegistry.empty()
            .withAdr(const Adr(
              id: 'ADR-001',
              title: 'A',
              status: AdrStatus.accepted,
              date: '2026-01-01',
              context: '',
              decision: '',
              consequences: '',
            ))
            .withAdr(const Adr(
              id: 'ADR-002',
              title: 'B',
              status: AdrStatus.proposed,
              date: '2026-01-01',
              context: '',
              decision: '',
              consequences: '',
            ));
        expect(registry.accepted.length, 1);
        expect(registry.proposed.length, 1);
      });

      test('getByTag filters correctly', () {
        final registry = AdrRegistry.empty()
            .withAdr(const Adr(
              id: 'ADR-001',
              title: 'A',
              status: AdrStatus.accepted,
              date: '2026-01-01',
              context: '',
              decision: '',
              consequences: '',
              tags: ['security', 'crypto'],
            ))
            .withAdr(const Adr(
              id: 'ADR-002',
              title: 'B',
              status: AdrStatus.accepted,
              date: '2026-01-01',
              context: '',
              decision: '',
              consequences: '',
              tags: ['architecture'],
            ));
        expect(registry.getByTag('security').length, 1);
        expect(registry.getByTag('architecture').length, 1);
        expect(registry.getByTag('nonexistent').length, 0);
      });

      test('equality', () {
        final a = AdrRegistry.empty().withAdr(const Adr(
              id: 'ADR-001',
              title: 'Test',
              status: AdrStatus.accepted,
              date: '2026-01-01',
              context: '',
              decision: '',
              consequences: '',
            ));
        final b = AdrRegistry.empty().withAdr(const Adr(
              id: 'ADR-001',
              title: 'Test',
              status: AdrStatus.accepted,
              date: '2026-01-01',
              context: '',
              decision: '',
              consequences: '',
            ));
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('PII audit', () {
      test('no PII in status labels', () {
        for (final status in AdrStatus.values) {
          expect(status.label, isNot(contains('@')));
          expect(status.label, isNot(contains('+')));
          expect(status.label, isNot(contains('phone')));
          expect(status.label, isNot(contains('email')));
        }
      });

      test('ADR IDs are not PII-shaped', () {
        const adr = Adr(
          id: 'ADR-001',
          title: 'Test',
          status: AdrStatus.accepted,
          date: '2026-01-01',
          context: '',
          decision: '',
          consequences: '',
        );
        expect(adr.id, isNot(contains(RegExp(r'[0-9]{10}'))));
        expect(adr.id, isNot(contains('@')));
      });
    });
  });
}
