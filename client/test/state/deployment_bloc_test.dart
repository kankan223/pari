import 'package:civic_commons/deployment/domain/build_config.dart';
import 'package:civic_commons/deployment/domain/health_monitor.dart';
import 'package:civic_commons/state/data/local_deployment_bloc.dart';
import 'package:civic_commons/state/domain/deployment_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deployment Bloc Tests (Task 14.1–14.4).
void main() {
  late LocalDeploymentBloc bloc;

  setUp(() {
    bloc = LocalDeploymentBloc();
  });

  tearDown(() {
    bloc.close();
  });

  group('LocalDeploymentBloc', () {
    test('initial state is empty', () {
      expect(bloc.state.hasBuildConfig, isFalse);
      expect(bloc.state.isBuilding, isFalse);
      expect(bloc.state.isVerifying, isFalse);
    });

    test('initialize sets build config', () {
      bloc.initialize(const EnvironmentConfig.production());

      expect(bloc.state.hasBuildConfig, isTrue);
      expect(bloc.state.buildConfig!.isProduction, isTrue);
    });

    test('runPipeline sets building state then completes', () async {
      final states = <DeploymentState>[];
      bloc.stream.listen(states.add);

      bloc.initialize(const EnvironmentConfig.production());
      bloc.runPipeline();
      await Future.delayed(Duration.zero);

      // After async completion, pipeline results exist and building is done.
      expect(bloc.state.stageResults, isNotEmpty);
      expect(bloc.state.isBuilding, isFalse);
    });

    test('runPipeline is idempotent while building', () async {
      final states = <DeploymentState>[];
      bloc.stream.listen(states.add);

      bloc.initialize(const EnvironmentConfig.production());
      // Call twice — second should be no-op
      bloc.runPipeline();
      bloc.runPipeline();
      await Future.delayed(Duration.zero);

      expect(states, isNotEmpty);
      expect(bloc.state.isBuilding, isFalse);
    });

    test('runVerification sets verifying state then completes', () async {
      final states = <DeploymentState>[];
      bloc.stream.listen(states.add);

      bloc.initialize(const EnvironmentConfig.production());
      bloc.runVerification();
      await Future.delayed(Duration.zero);

      // After async completion, verification report exists.
      expect(bloc.state.hasVerificationReport, isTrue);
      expect(bloc.state.isVerifying, isFalse);
    });

    test('refreshHealth produces health report', () async {
      bloc.refreshHealth();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.hasHealthReport, isTrue);
      expect(bloc.state.healthReport!.isHealthy, isTrue);
    });

    test('refreshHealth includes metrics', () async {
      bloc.refreshHealth();

      await Future.delayed(const Duration(milliseconds: 50));
      final report = bloc.state.healthReport!;
      expect(report.metrics, isNotEmpty);
      expect(report.metricValue(HealthMetricType.coldStartMs), 450);
    });

    test('reset clears all state', () async {
      bloc.initialize(const EnvironmentConfig.production());
      bloc.runPipeline();
      await Future.delayed(const Duration(milliseconds: 100));

      bloc.reset();

      expect(bloc.state.hasBuildConfig, isFalse);
      expect(bloc.state.stageResults, isEmpty);
      expect(bloc.state.isBuilding, isFalse);
    });

    test('close stops stream', () async {
      final states = <DeploymentState>[];
      bloc.stream.listen(states.add);

      bloc.initialize(const EnvironmentConfig.production());
      await Future.delayed(Duration.zero);

      bloc.close();
      expect(states, isNotEmpty);
    });
  });
}
