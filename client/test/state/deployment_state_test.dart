import 'package:civic_commons/deployment/domain/build_config.dart';
import 'package:civic_commons/deployment/domain/ci_cd_config.dart';
import 'package:civic_commons/deployment/domain/health_monitor.dart';
import 'package:civic_commons/deployment/domain/release_verifier.dart';
import 'package:civic_commons/state/domain/deployment_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deployment State Tests (Task 14.1–14.4).
void main() {
  group('DeploymentState', () {
    test('default state has no config', () {
      const state = DeploymentState();

      expect(state.hasBuildConfig, isFalse);
      expect(state.hasPipeline, isFalse);
      expect(state.hasHealthReport, isFalse);
      expect(state.hasVerificationReport, isFalse);
      expect(state.isBuilding, isFalse);
      expect(state.isVerifying, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('hasBuildConfig returns true when config is set', () {
      const state = DeploymentState(
        buildConfig: EnvironmentConfig.production(),
      );
      expect(state.hasBuildConfig, isTrue);
    });

    test('hasPipeline returns true when pipeline is set', () {
      const state = DeploymentState(
        pipeline: CiCdPipeline.flutterDefault(),
      );
      expect(state.hasPipeline, isTrue);
    });

    test('hasHealthReport returns true when report is set', () {
      final state = DeploymentState(
        healthReport: HealthReport.empty(),
      );
      expect(state.hasHealthReport, isTrue);
    });

    test('hasVerificationReport returns true when report is set', () {
      final state = DeploymentState(
        verificationReport: ReleaseVerificationReport.empty(),
      );
      expect(state.hasVerificationReport, isTrue);
    });

    test('allStagesPassed returns true when all stages passed', () {
      final state = DeploymentState(
        stageResults: [
          StageResultRecord(
            gate: QualityGate.staticAnalysis,
            result: StageResult.passed,
          ),
          StageResultRecord(
            gate: QualityGate.unitTests,
            result: StageResult.passed,
          ),
        ],
      );
      expect(state.allStagesPassed, isTrue);
    });

    test('allStagesPassed returns false when any stage failed', () {
      final state = DeploymentState(
        stageResults: [
          StageResultRecord(
            gate: QualityGate.staticAnalysis,
            result: StageResult.passed,
          ),
          StageResultRecord(
            gate: QualityGate.unitTests,
            result: StageResult.failed,
          ),
        ],
      );
      expect(state.allStagesPassed, isFalse);
    });

    test('verificationPassed delegates to report', () {
      final state = DeploymentState(
        verificationReport: ReleaseVerificationReport(
          buildProfile: 'production',
          appVersion: '1.0.0',
          buildNumber: 1,
          records: [
            VerificationRecord(
              check: VerificationCheck.binaryIntegrity,
              result: VerificationResult.passed,
              description: 'Passed',
            ),
          ],
        ),
      );
      expect(state.verificationPassed, isTrue);
    });

    test('statusLabel shows building when isBuilding', () {
      const state = DeploymentState(isBuilding: true);
      expect(state.statusLabel, 'Building...');
    });

    test('statusLabel shows verifying when isVerifying', () {
      const state = DeploymentState(isVerifying: true);
      expect(state.statusLabel, 'Verifying...');
    });

    test('statusLabel shows error when errorMessage present', () {
      const state = DeploymentState(errorMessage: 'Failed');
      expect(state.statusLabel, 'Error');
    });

    test('statusLabel shows ready when verification passed', () {
      final state = DeploymentState(
        verificationReport: ReleaseVerificationReport(
          buildProfile: 'production',
          appVersion: '1.0.0',
          buildNumber: 1,
          records: [
            VerificationRecord(
              check: VerificationCheck.binaryIntegrity,
              result: VerificationResult.passed,
              description: 'Passed',
            ),
          ],
        ),
      );
      expect(state.statusLabel, 'Ready for Release');
    });

    test('copyWith preserves unmodified fields', () {
      const original = DeploymentState(isBuilding: true);
      final copied = original.copyWith(errorMessage: 'Test error');

      expect(copied.isBuilding, isTrue);
      expect(copied.errorMessage, 'Test error');
    });

    test('equality by buildConfig, isBuilding, isVerifying', () {
      const a = DeploymentState(isBuilding: false, isVerifying: false);
      const b = DeploymentState(isBuilding: false, isVerifying: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('no PII in state', () {
      const state = DeploymentState();
      final str = state.toString();
      expect(str, isNot(contains('phone')));
      expect(str, isNot(contains('email')));
      expect(str, isNot(contains('+91')));
    });
  });
}
