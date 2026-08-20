import 'package:civic_commons/documentation/domain/contributor_guidelines.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.1 — Contributor Guidelines', () {
    group('ContributionType', () {
      test('has all contribution types', () {
        expect(ContributionType.values.length, 6);
      });

      test('label returns human-readable name', () {
        expect(ContributionType.bugFix.label, 'Bug Fix');
        expect(ContributionType.feature.label, 'Feature');
        expect(ContributionType.documentation.label, 'Documentation');
        expect(ContributionType.refactor.label, 'Refactoring');
        expect(ContributionType.testing.label, 'Testing');
        expect(ContributionType.securityFix.label, 'Security Fix');
      });

      test('commitPrefix returns conventional commit prefix', () {
        expect(ContributionType.bugFix.commitPrefix, 'fix');
        expect(ContributionType.feature.commitPrefix, 'feat');
        expect(ContributionType.documentation.commitPrefix, 'docs');
        expect(ContributionType.refactor.commitPrefix, 'refactor');
        expect(ContributionType.testing.commitPrefix, 'test');
        expect(ContributionType.securityFix.commitPrefix, 'fix(security)');
      });
    });

    group('ReviewRequirement', () {
      test('has all review levels', () {
        expect(ReviewRequirement.values.length, 4);
      });

      test('label returns human-readable name', () {
        expect(ReviewRequirement.none.label, 'No Review');
        expect(ReviewRequirement.single.label, '1 Reviewer');
        expect(ReviewRequirement.twoReviewers.label, '2 Reviewers');
        expect(ReviewRequirement.securityReview.label, 'Security Review');
      });
    });

    group('CodingStandard', () {
      test('constructs with required fields', () {
        const standard = CodingStandard(
          name: 'Zero PII',
          description: 'No phone numbers, emails, or hashes in UI.',
        );
        expect(standard.name, 'Zero PII');
        expect(standard.enforcedByLinter, isFalse);
      });

      test('equality by name', () {
        const a = CodingStandard(name: 'Test', description: 'A');
        const b = CodingStandard(name: 'Test', description: 'B');
        const c = CodingStandard(name: 'Other', description: 'A');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('ContributorGuidelines', () {
      test('constructs with defaults', () {
        const guidelines = ContributorGuidelines(
          projectName: 'Civic Commons',
        );
        expect(guidelines.projectName, 'Civic Commons');
        expect(guidelines.minFlutterVersion, '3.19.0');
        expect(guidelines.minDartVersion, '3.3.0');
        expect(guidelines.formatter, 'dart format');
        expect(guidelines.linter, 'flutter analyze');
        expect(guidelines.minCoveragePercent, 80);
      });

      test('reviewFor returns correct requirement', () {
        const guidelines = ContributorGuidelines(
          projectName: 'Civic Commons',
          reviewRequirements: {
            ContributionType.securityFix: ReviewRequirement.securityReview,
            ContributionType.bugFix: ReviewRequirement.single,
          },
        );
        expect(
          guidelines.reviewFor(ContributionType.securityFix),
          ReviewRequirement.securityReview,
        );
        expect(
          guidelines.reviewFor(ContributionType.bugFix),
          ReviewRequirement.single,
        );
        // Default is single reviewer
        expect(
          guidelines.reviewFor(ContributionType.feature),
          ReviewRequirement.single,
        );
      });

      test('equality by project name', () {
        const a = ContributorGuidelines(projectName: 'Test');
        const b = ContributorGuidelines(projectName: 'Test');
        const c = ContributorGuidelines(projectName: 'Other');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PII audit', () {
      test('no PII in contribution type labels', () {
        for (final type in ContributionType.values) {
          expect(type.label, isNot(contains('@')));
          expect(type.label, isNot(contains('+')));
          expect(type.label, isNot(contains('phone')));
          expect(type.label, isNot(contains('email')));
        }
      });

      test('no PII in review requirement labels', () {
        for (final req in ReviewRequirement.values) {
          expect(req.label, isNot(contains('@')));
          expect(req.label, isNot(contains('+')));
        }
      });

      test('no PII in commit prefixes', () {
        for (final type in ContributionType.values) {
          expect(type.commitPrefix, isNot(contains('@')));
          expect(type.commitPrefix, isNot(contains('+')));
        }
      });
    });
  });
}
