import 'package:civic_commons/documentation/domain/security_faq.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.4 — Security FAQ Domain', () {
    group('SecurityFaqCategory', () {
      test('has 6 categories', () {
        expect(SecurityFaqCategory.values.length, 6);
      });

      test('label returns human-readable name', () {
        expect(SecurityFaqCategory.encryption.label, 'Encryption & Data Protection');
        expect(SecurityFaqCategory.accountSecurity.label, 'Account Security');
        expect(SecurityFaqCategory.privacy.label, 'Privacy');
        expect(SecurityFaqCategory.dataSharing.label, 'Data Sharing');
        expect(SecurityFaqCategory.incidentReporting.label, 'Incident Reporting');
        expect(SecurityFaqCategory.compliance.label, 'Compliance & Regulations');
      });
    });

    group('SecurityFaqEntry', () {
      test('constructs with required fields', () {
        const entry = SecurityFaqEntry(
          id: 'SEC-FAQ-001',
          question: 'How is my data encrypted?',
          answer: 'All data is encrypted with AES-256-GCM.',
        );
        expect(entry.id, 'SEC-FAQ-001');
        expect(entry.category, SecurityFaqCategory.encryption);
        expect(entry.isActive, true);
        expect(entry.keywords, isEmpty);
      });

      test('equality by id', () {
        const a = SecurityFaqEntry(id: 'S1', question: 'Q1', answer: 'A1');
        const b = SecurityFaqEntry(id: 'S1', question: 'Q2', answer: 'A2');
        const c = SecurityFaqEntry(id: 'S2', question: 'Q1', answer: 'A1');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('SecurityFaqCollection', () {
      test('constructs with entries', () {
        const collection = SecurityFaqCollection(entries: {
          'S1': SecurityFaqEntry(id: 'S1', question: 'Q1', answer: 'A1'),
          'S2': SecurityFaqEntry(id: 'S2', question: 'Q2', answer: 'A2'),
        });
        expect(collection.count, 2);
      });

      test('getById returns entry', () {
        const collection = SecurityFaqCollection(entries: {
          'S1': SecurityFaqEntry(id: 'S1', question: 'Q1', answer: 'A1'),
        });
        expect(collection.getById('S1')!.question, 'Q1');
        expect(collection.getById('S99'), isNull);
      });

      test('getByCategory filters correctly', () {
        const collection = SecurityFaqCollection(entries: {
          'S1': SecurityFaqEntry(id: 'S1', question: 'Q', answer: 'A', category: SecurityFaqCategory.encryption),
          'S2': SecurityFaqEntry(id: 'S2', question: 'Q', answer: 'A', category: SecurityFaqCategory.privacy),
        });
        expect(collection.getByCategory(SecurityFaqCategory.encryption).length, 1);
        expect(collection.getByCategory(SecurityFaqCategory.privacy).length, 1);
      });

      test('active returns only active entries', () {
        const collection = SecurityFaqCollection(entries: {
          'S1': SecurityFaqEntry(id: 'S1', question: 'Q', answer: 'A', isActive: true),
          'S2': SecurityFaqEntry(id: 'S2', question: 'Q', answer: 'A', isActive: false),
        });
        expect(collection.active.length, 1);
      });

      test('search matches question, answer, and keywords', () {
        const collection = SecurityFaqCollection(entries: {
          'S1': SecurityFaqEntry(
            id: 'S1', question: 'How is encryption done?',
            answer: 'AES-256-GCM is used.',
            keywords: ['aes', 'gcm'],
          ),
          'S2': SecurityFaqEntry(
            id: 'S2', question: 'What about privacy?',
            answer: 'Zero-PII is enforced.',
            keywords: ['privacy', 'pii'],
          ),
        });
        expect(collection.search('aes').length, 1);
        expect(collection.search('privacy').length, 1);
        expect(collection.search('nonexistent').length, 0);
      });

      test('withEntry and withoutEntry are immutable', () {
        final empty = SecurityFaqCollection.empty();
        final withOne = empty.withEntry(
          const SecurityFaqEntry(id: 'S1', question: 'Q', answer: 'A'),
        );
        expect(empty.count, 0);
        expect(withOne.count, 1);
        final removed = withOne.withoutEntry('S1');
        expect(removed.count, 0);
        expect(withOne.count, 1);
      });

      test('categories returns distinct set', () {
        const collection = SecurityFaqCollection(entries: {
          'S1': SecurityFaqEntry(id: 'S1', question: 'Q', answer: 'A', category: SecurityFaqCategory.encryption),
          'S2': SecurityFaqEntry(id: 'S2', question: 'Q', answer: 'A', category: SecurityFaqCategory.encryption),
          'S3': SecurityFaqEntry(id: 'S3', question: 'Q', answer: 'A', category: SecurityFaqCategory.privacy),
        });
        expect(collection.categories.length, 2);
      });
    });

    group('PII audit', () {
      test('no PII in category labels', () {
        for (final cat in SecurityFaqCategory.values) {
          expect(cat.label, isNot(contains('@')));
          expect(cat.label, isNot(contains(RegExp(r'\+[0-9]{10}'))));
        }
      });
    });
  });
}
