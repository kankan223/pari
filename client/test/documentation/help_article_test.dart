import 'package:civic_commons/documentation/domain/help_article.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.3 — Help Article Domain', () {
    group('ArticleCategory', () {
      test('has 8 categories', () {
        expect(ArticleCategory.values.length, 8);
      });

      test('label returns human-readable name', () {
        expect(ArticleCategory.accountSetup.label, 'Account Setup');
        expect(ArticleCategory.messaging.label, 'Messaging');
        expect(ArticleCategory.civicParticipation.label, 'Civic Participation');
        expect(ArticleCategory.security.label, 'Security');
        expect(ArticleCategory.warRoom.label, 'War Room');
        expect(ArticleCategory.academy.label, 'Academy');
        expect(ArticleCategory.settings.label, 'Settings');
        expect(ArticleCategory.accessibility.label, 'Accessibility');
      });
    });

    group('ArticleAudience', () {
      test('has 4 audiences', () {
        expect(ArticleAudience.values.length, 4);
      });

      test('label returns human-readable name', () {
        expect(ArticleAudience.general.label, 'General');
        expect(ArticleAudience.accessibility.label, 'Accessibility');
        expect(ArticleAudience.lowBandwidth.label, 'Low Bandwidth');
        expect(ArticleAudience.technical.label, 'Technical');
      });
    });

    group('HowToStep', () {
      test('constructs with required fields', () {
        const step = HowToStep(
          number: 1,
          title: 'Open the app',
          instructions: 'Tap the Civic Commons icon on your home screen.',
        );
        expect(step.number, 1);
        expect(step.title, 'Open the app');
        expect(step.hasVisualAid, false);
      });

      test('hasVisualAid is true when screenshotAsset set', () {
        const withAsset = HowToStep(
          number: 1,
          title: 'Step',
          instructions: '...',
          screenshotAsset: 'assets/screenshots/step1.png',
        );
        expect(withAsset.hasVisualAid, true);
      });

      test('equality by number and title', () {
        const a = HowToStep(number: 1, title: 'A', instructions: 'x');
        const b = HowToStep(number: 1, title: 'A', instructions: 'y');
        const c = HowToStep(number: 2, title: 'A', instructions: 'x');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('HelpArticle', () {
      test('constructs with required fields', () {
        const article = HelpArticle(
          id: 'HELP-001',
          title: 'How to send a message',
          summary: 'Learn to send encrypted messages.',
          content: '## Sending Messages\n\nFollow these steps...',
        );
        expect(article.id, 'HELP-001');
        expect(article.category, ArticleCategory.accountSetup);
        expect(article.audience, ArticleAudience.general);
        expect(article.isPublished, true);
        expect(article.contentVersion, 1);
        expect(article.isHowTo, false);
        expect(article.stepCount, 0);
      });

      test('isHowTo is true when steps exist', () {
        const withSteps = HelpArticle(
          id: 'HELP-001',
          title: 'T',
          summary: 'S',
          content: 'C',
          steps: [
            HowToStep(number: 1, title: 'Step 1', instructions: 'Do this'),
            HowToStep(number: 2, title: 'Step 2', instructions: 'Then this'),
          ],
        );
        const withoutSteps = HelpArticle(
          id: 'HELP-002',
          title: 'T',
          summary: 'S',
          content: 'C',
        );
        expect(withSteps.isHowTo, true);
        expect(withSteps.stepCount, 2);
        expect(withoutSteps.isHowTo, false);
      });

      test('equality by id', () {
        const a = HelpArticle(id: 'HELP-1', title: 'A', summary: 's', content: 'c');
        const b = HelpArticle(id: 'HELP-1', title: 'B', summary: 't', content: 'd');
        const c = HelpArticle(id: 'HELP-2', title: 'A', summary: 's', content: 'c');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('HelpArticleCollection', () {
      test('constructs with articles', () {
        const collection = HelpArticleCollection(articles: {
          'HELP-1': HelpArticle(id: 'HELP-1', title: 'A', summary: 's', content: 'c'),
        });
        expect(collection.count, 1);
      });

      test('getById returns article', () {
        const collection = HelpArticleCollection(articles: {
          'HELP-1': HelpArticle(id: 'HELP-1', title: 'A', summary: 's', content: 'c'),
        });
        expect(collection.getById('HELP-1')!.title, 'A');
        expect(collection.getById('HELP-99'), isNull);
      });

      test('getByCategory filters correctly', () {
        const collection = HelpArticleCollection(articles: {
          'H1': HelpArticle(
            id: 'H1',
            title: 'A',
            summary: 's',
            content: 'c',
            category: ArticleCategory.security,
          ),
          'H2': HelpArticle(
            id: 'H2',
            title: 'B',
            summary: 's',
            content: 'c',
            category: ArticleCategory.messaging,
          ),
        });
        expect(collection.getByCategory(ArticleCategory.security).length, 1);
        expect(collection.getByCategory(ArticleCategory.messaging).length, 1);
      });

      test('getByAudience filters correctly', () {
        const collection = HelpArticleCollection(articles: {
          'H1': HelpArticle(
            id: 'H1',
            title: 'A',
            summary: 's',
            content: 'c',
            audience: ArticleAudience.accessibility,
          ),
          'H2': HelpArticle(
            id: 'H2',
            title: 'B',
            summary: 's',
            content: 'c',
            audience: ArticleAudience.general,
          ),
        });
        expect(
          collection.getByAudience(ArticleAudience.accessibility).length,
          1,
        );
      });

      test('published returns only published articles', () {
        const collection = HelpArticleCollection(articles: {
          'H1': HelpArticle(id: 'H1', title: 'A', summary: 's', content: 'c', isPublished: true),
          'H2': HelpArticle(id: 'H2', title: 'B', summary: 's', content: 'c', isPublished: false),
        });
        expect(collection.published.length, 1);
      });

      test('search matches title, summary, content, keywords', () {
        const collection = HelpArticleCollection(articles: {
          'H1': HelpArticle(
            id: 'H1',
            title: 'Send Messages',
            summary: 'Learn to chat',
            content: 'Open the messaging screen.',
            keywords: ['chat', 'e2ee'],
          ),
          'H2': HelpArticle(
            id: 'H2',
            title: 'View Ledger',
            summary: 'Browse posts',
            content: 'Navigate to the feed.',
            keywords: ['post', 'vote'],
          ),
        });
        expect(collection.search('chat').length, 1);
        expect(collection.search('ledger').length, 1);
        expect(collection.search('e2ee').length, 1);
        expect(collection.search('nonexistent').length, 0);
      });

      test('howToArticles returns only articles with steps', () {
        const collection = HelpArticleCollection(articles: {
          'H1': HelpArticle(
            id: 'H1',
            title: 'How-to',
            summary: 's',
            content: 'c',
            steps: [HowToStep(number: 1, title: 'Step', instructions: '...')],
          ),
          'H2': HelpArticle(id: 'H2', title: 'Reference', summary: 's', content: 'c'),
        });
        expect(collection.howToArticles.length, 1);
        expect(collection.howToArticles.first.id, 'H1');
      });

      test('withArticle and withoutArticle are immutable', () {
        final empty = HelpArticleCollection.empty();
        final withOne = empty.withArticle(
          const HelpArticle(id: 'H1', title: 'A', summary: 's', content: 'c'),
        );
        expect(empty.count, 0);
        expect(withOne.count, 1);
        final removed = withOne.withoutArticle('H1');
        expect(removed.count, 0);
        expect(withOne.count, 1);
      });

      test('categories returns distinct set', () {
        const collection = HelpArticleCollection(articles: {
          'H1': HelpArticle(id: 'H1', title: 'A', summary: 's', content: 'c', category: ArticleCategory.security),
          'H2': HelpArticle(id: 'H2', title: 'B', summary: 's', content: 'c', category: ArticleCategory.security),
          'H3': HelpArticle(id: 'H3', title: 'C', summary: 's', content: 'c', category: ArticleCategory.messaging),
        });
        expect(collection.categories.length, 2);
      });
    });

    group('PII audit', () {
      test('no PII in category labels', () {
        for (final cat in ArticleCategory.values) {
          expect(cat.label, isNot(contains('@')));
          expect(cat.label, isNot(contains(RegExp(r'\+[0-9]{10}'))));
        }
      });

      test('no PII in audience labels', () {
        for (final aud in ArticleAudience.values) {
          expect(aud.label, isNot(contains('@')));
        }
      });
    });
  });
}
