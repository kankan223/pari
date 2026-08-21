import 'package:civic_commons/documentation/domain/faq_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.3 — FAQ Entry Domain', () {
    group('FaqCategory', () {
      test('has 9 categories', () {
        expect(FaqCategory.values.length, 9);
      });

      test('label returns human-readable name', () {
        expect(FaqCategory.gettingStarted.label, 'Getting Started');
        expect(FaqCategory.account.label, 'Account');
        expect(FaqCategory.privacy.label, 'Privacy');
        expect(FaqCategory.messaging.label, 'Messaging');
        expect(FaqCategory.ledger.label, 'Ledger');
        expect(FaqCategory.warRoom.label, 'War Room');
        expect(FaqCategory.academy.label, 'Academy');
        expect(FaqCategory.technical.label, 'Technical');
        expect(FaqCategory.legal.label, 'Legal');
      });
    });

    group('FaqRelevance', () {
      test('has 4 levels', () {
        expect(FaqRelevance.values.length, 4);
      });

      test('label returns capitalized name', () {
        expect(FaqRelevance.low.label, 'Low');
        expect(FaqRelevance.critical.label, 'Critical');
      });

      test('weight returns ascending order', () {
        expect(FaqRelevance.low.weight, 0);
        expect(FaqRelevance.medium.weight, 1);
        expect(FaqRelevance.high.weight, 2);
        expect(FaqRelevance.critical.weight, 3);
      });
    });

    group('FaqEntry', () {
      test('constructs with required fields', () {
        const entry = FaqEntry(
          id: 'FAQ-001',
          question: 'How do I create an account?',
          answer: 'Navigate to the registration screen...',
        );
        expect(entry.id, 'FAQ-001');
        expect(entry.category, FaqCategory.technical);
        expect(entry.relevance, FaqRelevance.medium);
        expect(entry.isActive, true);
        expect(entry.locale, 'en');
        expect(entry.helpfulCount, 0);
        expect(entry.notHelpfulCount, 0);
      });

      test('helpfulnessRatio computes correctly', () {
        const entry = FaqEntry(
          id: 'FAQ-001',
          question: 'Q',
          answer: 'A',
          helpfulCount: 8,
          notHelpfulCount: 2,
        );
        expect(entry.helpfulnessRatio, 0.8);
        expect(entry.totalFeedbackCount, 10);
        expect(entry.hasFeedback, true);
      });

      test('helpfulnessRatio returns 0 when no feedback', () {
        const entry = FaqEntry(id: 'FAQ-001', question: 'Q', answer: 'A');
        expect(entry.helpfulnessRatio, 0.0);
        expect(entry.hasFeedback, false);
      });

      test('isHighlyHelpful requires >80% and feedback', () {
        const high = FaqEntry(
          id: 'FAQ-001',
          question: 'Q',
          answer: 'A',
          helpfulCount: 9,
          notHelpfulCount: 1,
        );
        const low = FaqEntry(
          id: 'FAQ-002',
          question: 'Q',
          answer: 'A',
          helpfulCount: 1,
          notHelpfulCount: 9,
        );
        const noFeedback = FaqEntry(id: 'FAQ-003', question: 'Q', answer: 'A');
        expect(high.isHighlyHelpful, true);
        expect(low.isHighlyHelpful, false);
        expect(noFeedback.isHighlyHelpful, false);
      });

      test('equality by id', () {
        const a = FaqEntry(id: 'FAQ-1', question: 'Q1', answer: 'A1');
        const b = FaqEntry(id: 'FAQ-1', question: 'Q2', answer: 'A2');
        const c = FaqEntry(id: 'FAQ-2', question: 'Q1', answer: 'A1');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('FaqCollection', () {
      test('constructs with entries', () {
        const collection = FaqCollection(entries: {
          'FAQ-1': FaqEntry(id: 'FAQ-1', question: 'Q1', answer: 'A1'),
          'FAQ-2': FaqEntry(id: 'FAQ-2', question: 'Q2', answer: 'A2'),
        });
        expect(collection.count, 2);
      });

      test('getById returns entry', () {
        const collection = FaqCollection(entries: {
          'FAQ-1': FaqEntry(id: 'FAQ-1', question: 'Q1', answer: 'A1'),
        });
        expect(collection.getById('FAQ-1')!.question, 'Q1');
        expect(collection.getById('FAQ-99'), isNull);
      });

      test('getByCategory filters correctly', () {
        const collection = FaqCollection(entries: {
          'FAQ-1': FaqEntry(
            id: 'FAQ-1',
            question: 'Q1',
            answer: 'A1',
            category: FaqCategory.privacy,
          ),
          'FAQ-2': FaqEntry(
            id: 'FAQ-2',
            question: 'Q2',
            answer: 'A2',
            category: FaqCategory.messaging,
          ),
        });
        expect(collection.getByCategory(FaqCategory.privacy).length, 1);
        expect(collection.getByCategory(FaqCategory.messaging).length, 1);
        expect(
          collection.getByCategory(FaqCategory.academy).length,
          0,
        );
      });

      test('search matches question, answer, and keywords', () {
        const collection = FaqCollection(entries: {
          'FAQ-1': FaqEntry(
            id: 'FAQ-1',
            question: 'How to send messages?',
            answer: 'Open the chat screen.',
            keywords: ['chat', 'message'],
          ),
          'FAQ-2': FaqEntry(
            id: 'FAQ-2',
            question: 'What is the ledger?',
            answer: 'A civic participation feed.',
            keywords: ['post', 'vote'],
          ),
        });
        // Match by keyword
        expect(collection.search('chat').length, 1);
        // Match by question content
        expect(collection.search('ledger').length, 1);
        // No match
        expect(collection.search('nonexistent').length, 0);
      });

      test('active returns only active entries', () {
        const collection = FaqCollection(entries: {
          'FAQ-1': FaqEntry(id: 'FAQ-1', question: 'Q', answer: 'A', isActive: true),
          'FAQ-2': FaqEntry(id: 'FAQ-2', question: 'Q', answer: 'A', isActive: false),
        });
        expect(collection.active.length, 1);
        expect(collection.active.first.id, 'FAQ-1');
      });

      test('withEntry and withoutEntry are immutable', () {
        final empty = FaqCollection.empty();
        final withOne = empty.withEntry(
          const FaqEntry(id: 'FAQ-1', question: 'Q', answer: 'A'),
        );
        expect(empty.count, 0);
        expect(withOne.count, 1);
        final removed = withOne.withoutEntry('FAQ-1');
        expect(removed.count, 0);
        expect(withOne.count, 1);
      });

      test('categories returns distinct set', () {
        const collection = FaqCollection(entries: {
          'FAQ-1': FaqEntry(id: 'FAQ-1', question: 'Q', answer: 'A', category: FaqCategory.privacy),
          'FAQ-2': FaqEntry(id: 'FAQ-2', question: 'Q', answer: 'A', category: FaqCategory.privacy),
          'FAQ-3': FaqEntry(id: 'FAQ-3', question: 'Q', answer: 'A', category: FaqCategory.messaging),
        });
        expect(collection.categories.length, 2);
      });
    });

    group('PII audit', () {
      test('no PII in category labels', () {
        for (final cat in FaqCategory.values) {
          expect(cat.label, isNot(contains('@')));
          expect(cat.label, isNot(contains(RegExp(r'\+[0-9]{10}'))));
        }
      });

      test('no PII in relevance labels', () {
        for (final rel in FaqRelevance.values) {
          expect(rel.label, isNot(contains('@')));
        }
      });
    });
  });
}
