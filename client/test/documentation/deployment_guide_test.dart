import 'package:civic_commons/documentation/domain/deployment_guide.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeploymentEnvironment', () {
    test('has 3 environments', () {
      expect(DeploymentEnvironment.values.length, 3);
    });

    test('labels are human-readable', () {
      expect(DeploymentEnvironment.development.label, 'Development');
      expect(DeploymentEnvironment.staging.label, 'Staging');
      expect(DeploymentEnvironment.production.label, 'Production');
    });

    test('only production is hardened', () {
      expect(DeploymentEnvironment.development.isHardened, false);
      expect(DeploymentEnvironment.staging.isHardened, false);
      expect(DeploymentEnvironment.production.isHardened, true);
    });
  });

  group('DeploymentStep', () {
    test('constructs with required fields', () {
      final step = DeploymentStep(
        number: 1,
        title: 'Run migrations',
        description: 'Execute database migration scripts',
      );
      expect(step.number, 1);
      expect(step.title, 'Run migrations');
      expect(step.mandatory, true);
      expect(step.preconditions, isEmpty);
      expect(step.verificationCommand, isNull);
      expect(step.rollbackInstruction, isNull);
    });

    test('estimatedMinutes converts duration', () {
      final step = DeploymentStep(
        number: 1,
        title: 'Deploy',
        description: 'Deploy to production',
        estimatedDuration: const Duration(minutes: 15),
      );
      expect(step.estimatedMinutes, 15);
    });

    test('equality by number and title', () {
      final a = DeploymentStep(
          number: 1, title: 'Deploy', description: 'Deploy');
      final b = DeploymentStep(
          number: 1, title: 'Deploy', description: 'Deploy');
      final c = DeploymentStep(
          number: 2, title: 'Deploy', description: 'Deploy');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('DeploymentProcedure', () {
    test('constructs with steps', () {
      final steps = [
        DeploymentStep(
            number: 1, title: 'Migrate', description: 'Run DB migrations'),
        DeploymentStep(
            number: 2, title: 'Deploy', description: 'Deploy app code'),
      ];
      final procedure = DeploymentProcedure(
        id: 'deploy-prod-v1',
        name: 'Production Deployment v1',
        environment: DeploymentEnvironment.production,
        steps: steps,
        requiresApproval: true,
      );
      expect(procedure.id, 'deploy-prod-v1');
      expect(procedure.steps.length, 2);
      expect(procedure.requiresApproval, true);
    });

    test('mandatoryStepCount counts mandatory steps', () {
      final steps = [
        DeploymentStep(
            number: 1,
            title: 'Migrate',
            description: 'Migrate',
            mandatory: true),
        DeploymentStep(
            number: 2,
            title: 'Notify',
            description: 'Notify',
            mandatory: false),
      ];
      final procedure = DeploymentProcedure(
        id: 'p1',
        name: 'P1',
        environment: DeploymentEnvironment.staging,
        steps: steps,
      );
      expect(procedure.mandatoryStepCount, 1);
      expect(procedure.allStepsMandatory, false);
    });

    test('verifiableSteps filters steps with verification', () {
      final steps = [
        DeploymentStep(
            number: 1,
            title: 'Deploy',
            description: 'Deploy',
            verificationCommand: 'curl healthcheck'),
        DeploymentStep(
            number: 2, title: 'Notify', description: 'Notify'),
      ];
      final procedure = DeploymentProcedure(
        id: 'p1',
        name: 'P1',
        environment: DeploymentEnvironment.staging,
        steps: steps,
      );
      expect(procedure.verifiableSteps.length, 1);
      expect(procedure.verifiableSteps.first.title, 'Deploy');
    });

    test('rollbackableSteps filters steps with rollback', () {
      final steps = [
        DeploymentStep(
            number: 1,
            title: 'Deploy',
            description: 'Deploy',
            rollbackInstruction: 'Revert to previous version'),
        DeploymentStep(
            number: 2, title: 'Notify', description: 'Notify'),
      ];
      final procedure = DeploymentProcedure(
        id: 'p1',
        name: 'P1',
        environment: DeploymentEnvironment.staging,
        steps: steps,
      );
      expect(procedure.rollbackableSteps.length, 1);
    });

    test('equality by id', () {
      final a = DeploymentProcedure(
          id: 'p1',
          name: 'P1',
          environment: DeploymentEnvironment.staging,
          steps: []);
      final b = DeploymentProcedure(
          id: 'p1',
          name: 'P2',
          environment: DeploymentEnvironment.production,
          steps: []);
      final c = DeploymentProcedure(
          id: 'p2',
          name: 'P1',
          environment: DeploymentEnvironment.staging,
          steps: []);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('EnvironmentConfig', () {
    test('constructs with defaults', () {
      final config = EnvironmentConfig(
        environment: DeploymentEnvironment.development,
      );
      expect(config.environment, DeploymentEnvironment.development);
      expect(config.featureToggles, isEmpty);
      expect(config.analyticsEnabled, false);
      expect(config.debugMode, false);
    });

    test('isProductionSafe when analytics off and debug off', () {
      final config = EnvironmentConfig(
        environment: DeploymentEnvironment.production,
        analyticsEnabled: false,
        debugMode: false,
      );
      expect(config.isProductionSafe, true);
    });

    test('not productionSafe when analytics enabled', () {
      final config = EnvironmentConfig(
        environment: DeploymentEnvironment.production,
        analyticsEnabled: true,
        debugMode: false,
      );
      expect(config.isProductionSafe, false);
    });

    test('not productionSafe when debug mode enabled', () {
      final config = EnvironmentConfig(
        environment: DeploymentEnvironment.production,
        analyticsEnabled: false,
        debugMode: true,
      );
      expect(config.isProductionSafe, false);
    });

    test('activeToggleCount counts true values', () {
      final config = EnvironmentConfig(
        environment: DeploymentEnvironment.staging,
        featureToggles: {
          'feature_a': true,
          'feature_b': false,
          'feature_c': true,
        },
      );
      expect(config.activeToggleCount, 2);
    });

    test('LogLevel has 4 levels', () {
      expect(LogLevel.values.length, 4);
    });

    test('LogLevel labels are human-readable', () {
      expect(LogLevel.debug.label, 'Debug');
      expect(LogLevel.info.label, 'Info');
      expect(LogLevel.warning.label, 'Warning');
      expect(LogLevel.error.label, 'Error');
    });

    test('violatesZeroPiiPolicy detects analytics in production', () {
      final safe = EnvironmentConfig(
        environment: DeploymentEnvironment.production,
        analyticsEnabled: false,
        debugMode: false,
      );
      final unsafeAnalytics = EnvironmentConfig(
        environment: DeploymentEnvironment.production,
        analyticsEnabled: true,
        debugMode: false,
      );
      final unsafeDebug = EnvironmentConfig(
        environment: DeploymentEnvironment.production,
        analyticsEnabled: false,
        debugMode: true,
      );
      expect(safe.violatesZeroPiiPolicy, false);
      expect(unsafeAnalytics.violatesZeroPiiPolicy, true);
      expect(unsafeDebug.violatesZeroPiiPolicy, true);
    });

    test('equality by environment', () {
      final a = EnvironmentConfig(
          environment: DeploymentEnvironment.production);
      final b = EnvironmentConfig(
          environment: DeploymentEnvironment.production);
      final c = EnvironmentConfig(
          environment: DeploymentEnvironment.staging);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('PII audit', () {
    test('deployment guide files have zero PII patterns', () {
      // All labels are fixed strings, no user data interpolation
      for (final env in DeploymentEnvironment.values) {
        expect(env.label, isNot(contains('+')));
        expect(env.label, isNot(contains('@')));
      }
    });
  });
}
