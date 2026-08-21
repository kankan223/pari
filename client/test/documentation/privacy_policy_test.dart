import 'package:civic_commons/documentation/domain/privacy_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.3 — Privacy Policy Domain', () {
    group('DataCategory', () {
      test('has 7 categories', () {
        expect(DataCategory.values.length, 7);
      });

      test('label returns human-readable name', () {
        expect(DataCategory.deviceIdentifiers.label, 'Device Identifiers');
        expect(DataCategory.messageContent.label, 'Message Content');
        expect(DataCategory.civicPosts.label, 'Civic Posts');
        expect(DataCategory.evidenceData.label, 'Evidence Data');
        expect(DataCategory.learningProgress.label, 'Learning Progress');
        expect(DataCategory.usageTelemetry.label, 'Usage Telemetry');
        expect(DataCategory.deviceMetadata.label, 'Device Metadata');
      });

      test('description returns non-empty string', () {
        for (final cat in DataCategory.values) {
          expect(cat.description.isNotEmpty, true);
        }
      });
    });

    group('ProcessingBasis', () {
      test('has 4 bases', () {
        expect(ProcessingBasis.values.length, 4);
      });

      test('label returns human-readable name', () {
        expect(ProcessingBasis.legitimateInterest.label, 'Legitimate Interest');
        expect(ProcessingBasis.consent.label, 'Consent');
        expect(ProcessingBasis.legalObligation.label, 'Legal Obligation');
        expect(ProcessingBasis.contractual.label, 'Contractual Necessity');
      });
    });

    group('RetentionPeriod', () {
      test('constructs with required fields', () {
        const rp = RetentionPeriod(
          dataCategory: DataCategory.deviceIdentifiers,
          description: 'Retained until user deletion',
          durationDays: -1,
        );
        expect(rp.dataCategory, DataCategory.deviceIdentifiers);
        expect(rp.isIndefinite, true);
        expect(rp.isShortTerm, false);
        expect(rp.userDeletable, true);
      });

      test('shortTerm is true for <=30 days', () {
        const short = RetentionPeriod(
          dataCategory: DataCategory.usageTelemetry,
          description: '30 days',
          durationDays: 30,
        );
        const long = RetentionPeriod(
          dataCategory: DataCategory.deviceMetadata,
          description: '365 days',
          durationDays: 365,
        );
        expect(short.isShortTerm, true);
        expect(long.isShortTerm, false);
      });

      test('autoPurge defaults to false', () {
        const rp = RetentionPeriod(
          dataCategory: DataCategory.deviceIdentifiers,
          description: 'Retained',
        );
        expect(rp.autoPurge, false);
      });

      test('equality by dataCategory', () {
        const a = RetentionPeriod(
          dataCategory: DataCategory.messageContent,
          description: 'E1',
        );
        const b = RetentionPeriod(
          dataCategory: DataCategory.messageContent,
          description: 'E2',
        );
        const c = RetentionPeriod(
          dataCategory: DataCategory.civicPosts,
          description: 'E1',
        );
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PrivacyRight', () {
      test('constructs with required fields', () {
        const right = PrivacyRight(
          id: 'right-access',
          name: 'Right to Access',
          description: 'Users can request a copy of their data.',
          exerciseInstructions: 'Contact privacy@civiccommons.org',
        );
        expect(right.id, 'right-access');
        expect(right.responseTimeDays, 30);
        expect(right.automated, false);
        expect(right.responseTimeLabel, '30 days');
      });

      test('equality by id', () {
        const a = PrivacyRight(
          id: 'r1',
          name: 'N1',
          description: 'D1',
          exerciseInstructions: 'E1',
        );
        const b = PrivacyRight(
          id: 'r1',
          name: 'N2',
          description: 'D2',
          exerciseInstructions: 'E2',
        );
        const c = PrivacyRight(
          id: 'r2',
          name: 'N1',
          description: 'D1',
          exerciseInstructions: 'E1',
        );
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PolicyClause', () {
      test('constructs with required fields', () {
        const clause = PolicyClause(
          number: '3.1',
          title: 'Data We Collect',
          content: 'We collect device identifiers...',
          relatedDataCategories: [DataCategory.deviceIdentifiers],
        );
        expect(clause.number, '3.1');
        expect(clause.relatesTo(DataCategory.deviceIdentifiers), true);
        expect(clause.relatesTo(DataCategory.messageContent), false);
      });

      test('equality by number', () {
        const a = PolicyClause(number: '1.0', title: 'A', content: 'x');
        const b = PolicyClause(number: '1.0', title: 'B', content: 'y');
        const c = PolicyClause(number: '2.0', title: 'A', content: 'x');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PrivacyPolicy', () {
      test('constructs with clauses and retention', () {
        const policy = PrivacyPolicy(
          appName: 'Civic Commons',
          version: '1.0',
          effectiveDate: '2026-08-21',
          lastUpdated: '2026-08-21',
          clauses: [
            PolicyClause(number: '1.0', title: 'Overview', content: '...'),
          ],
          retentionPeriods: [
            RetentionPeriod(
              dataCategory: DataCategory.deviceIdentifiers,
              description: 'Until deletion',
              durationDays: -1,
            ),
          ],
          rights: [
            PrivacyRight(
              id: 'right-access',
              name: 'Right to Access',
              description: 'Access your data.',
              exerciseInstructions: 'Email us.',
            ),
          ],
        );
        expect(policy.appName, 'Civic Commons');
        expect(policy.clauseCount, 1);
        expect(policy.coveredDataCategories, 1);
        expect(policy.rightsCount, 1);
      });

      test('getRetentionFor returns correct period', () {
        const policy = PrivacyPolicy(
          appName: 'App',
          version: '1.0',
          effectiveDate: '2026-01-01',
          lastUpdated: '2026-01-01',
          retentionPeriods: [
            RetentionPeriod(
              dataCategory: DataCategory.messageContent,
              description: 'Local only',
              durationDays: -1,
            ),
          ],
        );
        expect(
          policy.getRetentionFor(DataCategory.messageContent)!.isIndefinite,
          true,
        );
        expect(policy.getRetentionFor(DataCategory.civicPosts), isNull);
      });

      test('getClause returns correct clause', () {
        const policy = PrivacyPolicy(
          appName: 'App',
          version: '1.0',
          effectiveDate: '2026-01-01',
          lastUpdated: '2026-01-01',
          clauses: [
            PolicyClause(number: '3.1', title: 'Data Collection', content: '...'),
          ],
        );
        expect(policy.getClause('3.1')!.title, 'Data Collection');
        expect(policy.getClause('9.9'), isNull);
      });

      test('getRight returns correct right', () {
        const policy = PrivacyPolicy(
          appName: 'App',
          version: '1.0',
          effectiveDate: '2026-01-01',
          lastUpdated: '2026-01-01',
          rights: [
            PrivacyRight(
              id: 'right-deletion',
              name: 'Right to Deletion',
              description: 'Delete your data.',
              exerciseInstructions: 'Email us.',
            ),
          ],
        );
        expect(policy.getRight('right-deletion')!.name, 'Right to Deletion');
        expect(policy.getRight('nonexistent'), isNull);
      });

      test('requiresConsent returns true for evidence and telemetry', () {
        const policy = PrivacyPolicy(
          appName: 'App',
          version: '1.0',
          effectiveDate: '2026-01-01',
          lastUpdated: '2026-01-01',
        );
        expect(policy.requiresConsent(DataCategory.evidenceData), true);
        expect(policy.requiresConsent(DataCategory.usageTelemetry), true);
        expect(policy.requiresConsent(DataCategory.deviceIdentifiers), false);
        expect(policy.requiresConsent(DataCategory.messageContent), false);
      });

      test('indefiniteRetention lists correct categories', () {
        const policy = PrivacyPolicy(
          appName: 'App',
          version: '1.0',
          effectiveDate: '2026-01-01',
          lastUpdated: '2026-01-01',
          retentionPeriods: [
            RetentionPeriod(
              dataCategory: DataCategory.messageContent,
              description: 'Local',
              durationDays: -1,
            ),
            RetentionPeriod(
              dataCategory: DataCategory.usageTelemetry,
              description: '30 days',
              durationDays: 30,
            ),
          ],
        );
        expect(policy.indefiniteRetention.length, 1);
        expect(policy.indefiniteRetention.first, DataCategory.messageContent);
      });

      test('equality by appName and version', () {
        const a = PrivacyPolicy(
          appName: 'App',
          version: '1.0',
          effectiveDate: '2026-01-01',
          lastUpdated: '2026-01-01',
        );
        const b = PrivacyPolicy(
          appName: 'App',
          version: '1.0',
          effectiveDate: '2026-12-31',
          lastUpdated: '2026-12-31',
        );
        const c = PrivacyPolicy(
          appName: 'App',
          version: '2.0',
          effectiveDate: '2026-01-01',
          lastUpdated: '2026-01-01',
        );
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PII audit', () {
      test('no PII in data category labels', () {
        for (final cat in DataCategory.values) {
          expect(cat.label, isNot(contains('@')));
          expect(cat.label, isNot(contains(RegExp(r'\+[0-9]{10}'))));
        }
      });

      test('no PII in processing basis labels', () {
        for (final basis in ProcessingBasis.values) {
          expect(basis.label, isNot(contains('@')));
        }
      });

      test('default privacy contact is role-based, not personal', () {
        const policy = PrivacyPolicy(
          appName: 'App',
          version: '1.0',
          effectiveDate: '2026-01-01',
          lastUpdated: '2026-01-01',
        );
        expect(policy.privacyContactEmail, contains('@'));
        expect(policy.privacyContactEmail, isNot(contains('+91')));
      });
    });
  });
}
