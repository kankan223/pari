import 'package:civic_commons/documentation/domain/bug_bounty.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.4 — Bug Bounty Program Domain', () {
    group('BountyRewardTier', () {
      test('has 4 tiers', () {
        expect(BountyRewardTier.values.length, 4);
      });

      test('label returns capitalized name', () {
        expect(BountyRewardTier.low.label, 'Low');
        expect(BountyRewardTier.medium.label, 'Medium');
        expect(BountyRewardTier.high.label, 'High');
        expect(BountyRewardTier.critical.label, 'Critical');
      });

      test('weight returns ascending order', () {
        expect(BountyRewardTier.low.weight, 0);
        expect(BountyRewardTier.medium.weight, 1);
        expect(BountyRewardTier.high.weight, 2);
        expect(BountyRewardTier.critical.weight, 3);
      });

      test('rewardRange returns description', () {
        expect(BountyRewardTier.low.rewardRange, 'Low reward');
        expect(BountyRewardTier.critical.rewardRange, 'Critical reward');
      });
    });

    group('BountySubmissionStatus', () {
      test('has 8 statuses', () {
        expect(BountySubmissionStatus.values.length, 8);
      });

      test('label returns human-readable name', () {
        expect(BountySubmissionStatus.submitted.label, 'Submitted');
        expect(BountySubmissionStatus.underReview.label, 'Under Review');
        expect(BountySubmissionStatus.confirmed.label, 'Confirmed');
        expect(BountySubmissionStatus.fixInProgress.label, 'Fix In Progress');
        expect(BountySubmissionStatus.fixDeployed.label, 'Fix Deployed');
        expect(BountySubmissionStatus.rewardIssued.label, 'Reward Issued');
        expect(BountySubmissionStatus.rejected.label, 'Rejected');
        expect(BountySubmissionStatus.duplicate.label, 'Duplicate');
      });
    });

    group('BountyScope', () {
      test('constructs with in-scope and out-of-scope', () {
        const scope = BountyScope(
          inScope: ['messaging', 'ledger', 'war room'],
          outOfScope: ['third-party services'],
          allowedMethods: ['static analysis', 'manual testing'],
          prohibitedMethods: ['denial of service'],
        );
        expect(scope.inScope.length, 3);
        expect(scope.outOfScope.length, 1);
      });

      test('isInScope matches case-insensitively', () {
        const scope = BountyScope(inScope: ['messaging', 'ledger']);
        expect(scope.isInScope('Messaging'), true);
        expect(scope.isInScope('Ledger'), true);
        expect(scope.isInScope('academy'), false);
      });
    });

    group('BountySubmission', () {
      test('constructs with required fields', () {
        const sub = BountySubmission(
          id: 'BB-2026-001',
          title: 'XSS in profile',
          description: 'Cross-site scripting vulnerability.',
          affectedComponent: 'ProfileScreen',
          severity: BountyRewardTier.medium,
          submittedDate: '2026-08-21',
          reporterHandle: 'AN-0042',
          stepsToReproduce: '1. Navigate to profile...',
        );
        expect(sub.id, 'BB-2026-001');
        expect(sub.status, BountySubmissionStatus.submitted);
        expect(sub.isAccepted, false);
        expect(sub.isRejected, false);
      });

      test('isAccepted for confirmed and beyond', () {
        const confirmed = BountySubmission(
          id: 'S1', title: 'T', description: 'D', affectedComponent: 'C',
          severity: BountyRewardTier.high, status: BountySubmissionStatus.confirmed,
          submittedDate: '2026-01-01', reporterHandle: 'AN-0001', stepsToReproduce: 'S',
        );
        const rewardIssued = BountySubmission(
          id: 'S2', title: 'T', description: 'D', affectedComponent: 'C',
          severity: BountyRewardTier.critical, status: BountySubmissionStatus.rewardIssued,
          submittedDate: '2026-01-01', reporterHandle: 'AN-0002', stepsToReproduce: 'S',
        );
        const submitted = BountySubmission(
          id: 'S3', title: 'T', description: 'D', affectedComponent: 'C',
          severity: BountyRewardTier.low, submittedDate: '2026-01-01',
          reporterHandle: 'AN-0003', stepsToReproduce: 'S',
        );
        expect(confirmed.isAccepted, true);
        expect(rewardIssued.isAccepted, true);
        expect(submitted.isAccepted, false);
      });

      test('isRejected for rejected and duplicate', () {
        const rejected = BountySubmission(
          id: 'S1', title: 'T', description: 'D', affectedComponent: 'C',
          severity: BountyRewardTier.medium, status: BountySubmissionStatus.rejected,
          submittedDate: '2026-01-01', reporterHandle: 'AN-0001', stepsToReproduce: 'S',
        );
        const duplicate = BountySubmission(
          id: 'S2', title: 'T', description: 'D', affectedComponent: 'C',
          severity: BountyRewardTier.high, status: BountySubmissionStatus.duplicate,
          submittedDate: '2026-01-01', reporterHandle: 'AN-0002', stepsToReproduce: 'S',
        );
        expect(rejected.isRejected, true);
        expect(duplicate.isRejected, true);
      });

      test('equality by id', () {
        const a = BountySubmission(
          id: 'B1', title: 'A', description: 'D', affectedComponent: 'C',
          severity: BountyRewardTier.low, submittedDate: '2026-01-01',
          reporterHandle: 'AN-0001', stepsToReproduce: 'S',
        );
        const b = BountySubmission(
          id: 'B1', title: 'B', description: 'E', affectedComponent: 'X',
          severity: BountyRewardTier.critical, submittedDate: '2026-12-31',
          reporterHandle: 'AN-9999', stepsToReproduce: 'Y',
        );
        const c = BountySubmission(
          id: 'B2', title: 'A', description: 'D', affectedComponent: 'C',
          severity: BountyRewardTier.low, submittedDate: '2026-01-01',
          reporterHandle: 'AN-0001', stepsToReproduce: 'S',
        );
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('BugBountyProgram', () {
      test('constructs with scope and guidelines', () {
        const program = BugBountyProgram(
          programName: 'Civic Commons Bug Bounty',
          version: '1.0',
          description: 'Security bug bounty program for Civic Commons.',
          scope: BountyScope(
            inScope: ['messaging', 'identity'],
            allowedMethods: ['static analysis'],
          ),
          rewardTiers: [BountyRewardTier.low, BountyRewardTier.medium, BountyRewardTier.high, BountyRewardTier.critical],
          submissionGuidelines: ['Submit via email', 'Include reproduction steps'],
          safeHarborProvisions: ['We will not pursue legal action', 'Safe harbor for good-faith testing'],
        );
        expect(program.guidelineCount, 2);
        expect(program.safeHarborCount, 2);
        expect(program.isActive, true);
      });

      test('isMethodAllowed checks allowlist and blocklist', () {
        const program = BugBountyProgram(
          programName: 'Bounty',
          version: '1.0',
          description: 'D',
          scope: BountyScope(
            allowedMethods: ['static analysis', 'manual testing'],
            prohibitedMethods: ['denial of service'],
          ),
        );
        expect(program.isMethodAllowed('static analysis'), true);
        expect(program.isMethodAllowed('manual testing'), true);
        expect(program.isMethodAllowed('denial of service'), false);
        expect(program.isMethodAllowed('social engineering'), false);
      });

      test('equality by programName and version', () {
        const a = BugBountyProgram(programName: 'B', version: '1.0', description: 'D');
        const b = BugBountyProgram(programName: 'B', version: '1.0', description: 'E');
        const c = BugBountyProgram(programName: 'B', version: '2.0', description: 'D');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PII audit', () {
      test('no PII in reward tier labels', () {
        for (final tier in BountyRewardTier.values) {
          expect(tier.label, isNot(contains('@')));
          expect(tier.label, isNot(contains(RegExp(r'\+[0-9]{10}'))));
        }
      });

      test('no PII in submission status labels', () {
        for (final status in BountySubmissionStatus.values) {
          expect(status.label, isNot(contains('@')));
        }
      });

      test('program contact is role-based, not personal', () {
        const program = BugBountyProgram(
          programName: 'B', version: '1.0', description: 'D',
        );
        expect(program.contactEmail, contains('@'));
        expect(program.contactEmail, isNot(contains('+91')));
      });
    });
  });
}
