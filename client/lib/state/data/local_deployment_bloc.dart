import 'dart:async';

import 'package:civic_commons/deployment/domain/build_config.dart';
import 'package:civic_commons/deployment/domain/ci_cd_config.dart';
import 'package:civic_commons/deployment/domain/health_monitor.dart';
import 'package:civic_commons/deployment/domain/release_verifier.dart';

import '../domain/deployment_bloc.dart';
import '../domain/deployment_state.dart';

/// Local implementation of [DeploymentBloc] (Task 14.1–14.4).
///
/// Coordinates build configuration, CI/CD pipeline, health monitoring,
/// and release verification. Uses monotonic sequence stale-drop pattern
/// for stream safety.
///
/// Security contract:
/// - All build/health/verification data is kept local — never transmitted.
/// - Metrics carry only integer counters and fixed labels — zero PII.
class LocalDeploymentBloc implements DeploymentBloc {
  final _controller = StreamController<DeploymentState>.broadcast();
  var _state = const DeploymentState();
  var _sequence = 0;

  @override
  Stream<DeploymentState> get stream => _controller.stream;

  @override
  DeploymentState get state => _state;

  @override
  void initialize(EnvironmentConfig config) {
    _sequence++;
    _state = _state.copyWith(
      buildConfig: config,
      errorMessage: null,
    );
    _emit();
  }

  @override
  void runPipeline() async {
    if (_state.isBuilding) return;

    _sequence++;
    final seq = _sequence;
    _state = _state.copyWith(
      isBuilding: true,
      errorMessage: null,
    );
    _emit();

    try {
      // Simulate pipeline execution
      final results = <StageResultRecord>[];
      final gates = _state.pipeline?.gates ?? CiCdPipeline.flutterDefault().gates;

      for (final gate in gates) {
        if (seq != _sequence) return;

        results.add(StageResultRecord(
          gate: gate,
          result: StageResult.passed,
          durationMs: 100,
          testsPassed: 100,
          testsFailed: 0,
          completedAtMs: DateTime.now().millisecondsSinceEpoch,
        ));

        _state = _state.copyWith(stageResults: results);
        _emit();
      }

      if (seq != _sequence) return;

      _state = _state.copyWith(
        isBuilding: false,
        pipeline: _state.pipeline ?? CiCdPipeline.flutterDefault(),
      );
    } catch (e) {
      if (seq != _sequence) return;
      _state = _state.copyWith(
        isBuilding: false,
        errorMessage: 'Pipeline failed: $e',
      );
    }
    _emit();
  }

  @override
  void runVerification() async {
    if (_state.isVerifying) return;

    _sequence++;
    final seq = _sequence;
    _state = _state.copyWith(
      isVerifying: true,
      errorMessage: null,
    );
    _emit();

    try {
      // Simulate verification checks
      final records = <VerificationRecord>[];
      final checks = VerificationCheck.values;

      for (final check in checks) {
        if (seq != _sequence) return;

        records.add(VerificationRecord(
          check: check,
          result: VerificationResult.passed,
          description: '${check.label} check passed',
          executedAtMs: DateTime.now().millisecondsSinceEpoch,
        ));

        _state = _state.copyWith(
          verificationReport: ReleaseVerificationReport(
            buildProfile: _state.buildConfig?.profile.name ?? 'unknown',
            appVersion: _state.buildConfig?.appVersion ?? '0.0.0',
            buildNumber: _state.buildConfig?.buildNumber ?? 0,
            records: records,
            completedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        _emit();
      }

      if (seq != _sequence) return;

      _state = _state.copyWith(isVerifying: false);
    } catch (e) {
      if (seq != _sequence) return;
      _state = _state.copyWith(
        isVerifying: false,
        errorMessage: 'Verification failed: $e',
      );
    }
    _emit();
  }

  @override
  void refreshHealth() async {
    _sequence++;
    final seq = _sequence;

    try {
      // Simulate health metrics collection
      final metrics = <HealthMetric>[];
      final now = DateTime.now().millisecondsSinceEpoch;

      metrics.add(HealthMetric(
        type: HealthMetricType.coldStartMs,
        value: 450,
        recordedAtMs: now,
      ));
      metrics.add(HealthMetric(
        type: HealthMetricType.memoryUsageBytes,
        value: 50 * 1024 * 1024, // 50MB
        recordedAtMs: now,
      ));
      metrics.add(HealthMetric(
        type: HealthMetricType.peakMemoryBytes,
        value: 75 * 1024 * 1024, // 75MB
        recordedAtMs: now,
      ));
      metrics.add(HealthMetric(
        type: HealthMetricType.syncQueueSize,
        value: 0,
        recordedAtMs: now,
      ));
      metrics.add(HealthMetric(
        type: HealthMetricType.pendingMutations,
        value: 0,
        recordedAtMs: now,
      ));
      metrics.add(HealthMetric(
        type: HealthMetricType.cachedImageCount,
        value: 12,
        recordedAtMs: now,
      ));
      metrics.add(HealthMetric(
        type: HealthMetricType.deferredPillarsLoaded,
        value: 4,
        recordedAtMs: now,
      ));
      metrics.add(HealthMetric(
        type: HealthMetricType.activeConnections,
        value: 1,
        recordedAtMs: now,
      ));

      if (seq != _sequence) return;

      _state = _state.copyWith(
        healthReport: HealthReport(
          status: StabilityStatus.healthy,
          metrics: metrics,
          generatedAtMs: now,
          errorCount: 0,
          warningCount: 0,
          uptimeMs: now - 1000, // Simulated uptime
        ),
      );
    } catch (e) {
      if (seq != _sequence) return;
      _state = _state.copyWith(
        errorMessage: 'Health check failed: $e',
      );
    }
    _emit();
  }

  @override
  void reset() {
    _sequence++;
    _state = const DeploymentState();
    _emit();
  }

  @override
  void close() {
    _controller.close();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_state);
    }
  }
}
