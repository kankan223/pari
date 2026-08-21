import 'package:civic_commons/documentation/domain/user_guide.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.3 — User Guide Domain', () {
    group('GuideAudience', () {
      test('has 4 audience types', () {
        expect(GuideAudience.values.length, 4);
      });

      test('label returns human-readable name', () {
        expect(GuideAudience.newUsers.label, 'New Users');
        expect(GuideAudience.returningUsers.label, 'Returning Users');
        expect(GuideAudience.advancedUsers.label, 'Advanced Users');
        expect(GuideAudience.administrators.label, 'Administrators');
      });
    });

    group('DifficultyLevel', () {
      test('has 3 levels', () {
        expect(DifficultyLevel.values.length, 3);
      });

      test('label returns capitalized name', () {
        expect(DifficultyLevel.beginner.label, 'Beginner');
        expect(DifficultyLevel.intermediate.label, 'Intermediate');
        expect(DifficultyLevel.advanced.label, 'Advanced');
      });

      test('weight returns ascending order', () {
        expect(DifficultyLevel.beginner.weight, 0);
        expect(DifficultyLevel.intermediate.weight, 1);
        expect(DifficultyLevel.advanced.weight, 2);
      });
    });

    group('GuideSection', () {
      test('constructs with required fields', () {
        const section = GuideSection(
          id: 'getting-started-otp',
          title: 'Requesting an OTP',
          content: '## How to request an OTP\n\nStep 1...',
        );
        expect(section.id, 'getting-started-otp');
        expect(section.title, 'Requesting an OTP');
        expect(section.audience, GuideAudience.newUsers);
        expect(section.difficulty, DifficultyLevel.beginner);
        expect(section.readingTimeMinutes, 5);
        expect(section.prerequisites, isEmpty);
      });

      test('hasPrerequisites is true when prerequisites exist', () {
        const withPrereqs = GuideSection(
          id: 's1',
          title: 'Advanced',
          content: '...',
          prerequisites: ['getting-started'],
        );
        const withoutPrereqs = GuideSection(
          id: 's2',
          title: 'Basic',
          content: '...',
        );
        expect(withPrereqs.hasPrerequisites, true);
        expect(withoutPrereqs.hasPrerequisites, false);
      });

      test('equality by id', () {
        const a = GuideSection(id: 'S1', title: 'A', content: 'x');
        const b = GuideSection(id: 'S1', title: 'B', content: 'y');
        const c = GuideSection(id: 'S2', title: 'A', content: 'x');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('GuideChapter', () {
      test('constructs with sections', () {
        const chapter = GuideChapter(
          number: 1,
          title: 'Getting Started',
          description: 'Learn the basics',
          sections: [
            GuideSection(id: 's1', title: 'Welcome', content: '...'),
            GuideSection(id: 's2', title: 'OTP', content: '...'),
          ],
        );
        expect(chapter.number, 1);
        expect(chapter.sectionCount, 2);
      });

      test('totalReadingTimeMinutes sums section times', () {
        const chapter = GuideChapter(
          number: 1,
          title: 'T',
          description: 'D',
          sections: [
            GuideSection(id: 's1', title: 'A', content: '...', readingTimeMinutes: 3),
            GuideSection(id: 's2', title: 'B', content: '...', readingTimeMinutes: 7),
          ],
        );
        expect(chapter.totalReadingTimeMinutes, 10);
      });

      test('allBeginner is true when all sections are beginner', () {
        const allBeginner = GuideChapter(
          number: 1,
          title: 'T',
          description: 'D',
          sections: [
            GuideSection(id: 's1', title: 'A', content: '...', difficulty: DifficultyLevel.beginner),
          ],
        );
        const mixed = GuideChapter(
          number: 2,
          title: 'T',
          description: 'D',
          sections: [
            GuideSection(id: 's1', title: 'A', content: '...', difficulty: DifficultyLevel.advanced),
          ],
        );
        expect(allBeginner.allBeginner, true);
        expect(mixed.allBeginner, false);
      });

      test('equality by number', () {
        const a = GuideChapter(number: 1, title: 'A', description: 'd');
        const b = GuideChapter(number: 1, title: 'B', description: 'e');
        const c = GuideChapter(number: 2, title: 'A', description: 'd');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('UserGuide', () {
      test('constructs with chapters', () {
        const guide = UserGuide(
          appName: 'Civic Commons',
          version: '1.0',
          lastUpdated: '2026-08-21',
          chapters: [
            GuideChapter(
              number: 1,
              title: 'Basics',
              description: 'Learn the basics',
              sections: [
                GuideSection(id: 's1', title: 'Welcome', content: '...'),
              ],
            ),
          ],
          locales: ['en', 'hi'],
        );
        expect(guide.appName, 'Civic Commons');
        expect(guide.chapterCount, 1);
        expect(guide.totalSectionCount, 1);
        expect(guide.locales, ['en', 'hi']);
      });

      test('findSection returns section across chapters', () {
        const guide = UserGuide(
          appName: 'App',
          version: '1.0',
          lastUpdated: '2026-08-21',
          chapters: [
            GuideChapter(
              number: 1,
              title: 'C1',
              description: 'd',
              sections: [
                GuideSection(id: 'target', title: 'Found', content: '...'),
              ],
            ),
            GuideChapter(
              number: 2,
              title: 'C2',
              description: 'd',
              sections: [
                GuideSection(id: 'other', title: 'Other', content: '...'),
              ],
            ),
          ],
        );
        expect(guide.findSection('target')!.title, 'Found');
        expect(guide.findSection('missing'), isNull);
      });

      test('chaptersForAudience filters correctly', () {
        const guide = UserGuide(
          appName: 'App',
          version: '1.0',
          lastUpdated: '2026-08-21',
          chapters: [
            GuideChapter(
              number: 1,
              title: 'Basics',
              description: 'd',
              sections: [
                GuideSection(
                  id: 's1',
                  title: 'For New',
                  content: '...',
                  audience: GuideAudience.newUsers,
                ),
              ],
            ),
            GuideChapter(
              number: 2,
              title: 'Advanced',
              description: 'd',
              sections: [
                GuideSection(
                  id: 's2',
                  title: 'For Admin',
                  content: '...',
                  audience: GuideAudience.administrators,
                ),
              ],
            ),
          ],
        );
        final adminChapters = guide.chaptersForAudience(GuideAudience.administrators);
        expect(adminChapters.length, 1);
        expect(adminChapters.first.number, 2);
      });

      test('equality by appName and version', () {
        const a = UserGuide(appName: 'App', version: '1.0', lastUpdated: '2026-01-01');
        const b = UserGuide(appName: 'App', version: '1.0', lastUpdated: '2026-12-31');
        const c = UserGuide(appName: 'App', version: '2.0', lastUpdated: '2026-01-01');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PII audit', () {
      test('no PII in audience labels', () {
        for (final audience in GuideAudience.values) {
          expect(audience.label, isNot(contains('@')));
          expect(audience.label, isNot(contains(RegExp(r'\+[0-9]{10}'))));
        }
      });

      test('no PII in difficulty labels', () {
        for (final level in DifficultyLevel.values) {
          expect(level.label, isNot(contains('@')));
        }
      });
    });
  });
}
