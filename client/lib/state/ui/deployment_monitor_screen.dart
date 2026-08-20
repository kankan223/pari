import 'package:flutter/material.dart';

import '../../deployment/domain/build_config.dart';
import '../../deployment/domain/ci_cd_config.dart';
import '../../deployment/domain/health_monitor.dart';
import '../../deployment/domain/release_verifier.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/deployment_bloc.dart';
import '../domain/deployment_state.dart';

/// UI screen for deployment monitoring (Task 14.1–14.4).
///
/// Displays build configuration, CI/CD pipeline status, health metrics,
/// and release verification results. Wrapped in SecureScreenWrapper
/// for FLAG_SECURE protection.
///
/// Security contract:
/// - All displayed data is deployment metadata only — zero PII.
/// - Build configs carry version strings and profile labels, never secrets.
/// - FLAG_SECURE prevents screenshots of deployment monitoring data.
class DeploymentMonitorScreen extends StatelessWidget {
  final DeploymentBloc bloc;

  const DeploymentMonitorScreen({super.key, required this.bloc});

  @override
  Widget build(BuildContext context) {
    return SecureScreenWrapper(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Deployment Monitor'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Health',
              onPressed: () => bloc.refreshHealth(),
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Run Pipeline',
              onPressed: () => bloc.runPipeline(),
            ),
            IconButton(
              icon: const Icon(Icons.verified),
              tooltip: 'Run Verification',
              onPressed: () => bloc.runVerification(),
            ),
          ],
        ),
        body: StreamBuilder<DeploymentState>(
          stream: bloc.stream,
          initialData: bloc.state,
          builder: (context, snapshot) {
            final state = snapshot.data!;
            return _buildBody(context, state);
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DeploymentState state) {
    if (state.isBuilding) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Running CI/CD pipeline...'),
          ],
        ),
      );
    }

    if (state.isVerifying) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Running release verification...'),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Build Configuration
        if (state.buildConfig != null) ...[
          _buildBuildConfigCard(state.buildConfig!),
          const SizedBox(height: 16),
        ],

        // CI/CD Pipeline Status
        if (state.stageResults.isNotEmpty) ...[
          _buildPipelineCard(state),
          const SizedBox(height: 16),
        ],

        // Health Report
        if (state.healthReport != null) ...[
          _buildHealthCard(state.healthReport!),
          const SizedBox(height: 16),
        ],

        // Release Verification
        if (state.verificationReport != null) ...[
          _buildVerificationCard(state.verificationReport!),
          const SizedBox(height: 16),
        ],

        // Error State
        if (state.errorMessage != null) ...[
          _buildErrorCard(state.errorMessage!),
          const SizedBox(height: 16),
        ],

        // Empty State
        if (!state.hasBuildConfig &&
            state.stageResults.isEmpty &&
            !state.hasHealthReport &&
            !state.hasVerificationReport)
          _buildEmptyState(),
      ],
    );
  }

  Widget _buildBuildConfigCard(EnvironmentConfig config) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  config.isProduction
                      ? Icons.rocket_launch
                      : Icons.build,
                  color: config.isProduction ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  'Build Configuration',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatRow('Profile', config.profile.label),
            _buildStatRow('Version', config.appVersion),
            _buildStatRow('Build', '#${config.buildNumber}'),
            _buildStatRow('Min SDK', config.minSdkVersion),
            _buildStatRow('Target SDK', config.targetSdkVersion),
            _buildStatRow('Obfuscation', config.obfuscateCode ? 'Yes' : 'No'),
            _buildStatRow('Strip Debug', config.stripDebugSymbols ? 'Yes' : 'No'),
            _buildStatRow('Tree Shaking', config.treeShaking ? 'Yes' : 'No'),
            const Divider(),
            const Text(
              'Target Platforms:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: config.targetPlatforms
                  .map((p) => Chip(label: Text(p.label)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPipelineCard(DeploymentState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.allStagesPassed
                      ? Icons.check_circle
                      : Icons.warning,
                  color: state.allStagesPassed ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  'CI/CD Pipeline',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: state.allStagesPassed
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${state.stagesPassedCount}/${state.stagesTotalCount} PASSED',
                    style: TextStyle(
                      color: state.allStagesPassed ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...state.stageResults.map((r) => _buildStageTile(r)),
          ],
        ),
      ),
    );
  }

  Widget _buildStageTile(StageResultRecord record) {
    return ListTile(
      leading: Icon(
        record.result.isSuccess
            ? Icons.check_circle
            : record.result.isFailure
                ? Icons.error
                : Icons.hourglass_empty,
        color: record.result.isSuccess
            ? Colors.green
            : record.result.isFailure
                ? Colors.red
                : Colors.grey,
      ),
      title: Text(record.gate.label),
      subtitle: Text(
        'Tests: ${record.testsPassed}/${record.totalTests}',
      ),
      trailing: Text(
        record.result.isSuccess ? 'PASS' : 'FAIL',
        style: TextStyle(
          color: record.result.isSuccess ? Colors.green : Colors.red,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildHealthCard(HealthReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  report.isHealthy
                      ? Icons.favorite
                      : report.isDegraded
                          ? Icons.warning
                          : Icons.error,
                  color: report.isHealthy
                      ? Colors.green
                      : report.isDegraded
                          ? Colors.orange
                          : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'Health Report',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: report.isHealthy
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    report.status.label.toUpperCase(),
                    style: TextStyle(
                      color: report.isHealthy ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              'Uptime',
              '${report.uptimeMinutes.toStringAsFixed(1)} min',
            ),
            _buildStatRow('Errors', '${report.errorCount}'),
            _buildStatRow('Warnings', '${report.warningCount}'),
            const Divider(),
            const Text(
              'Metrics:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            ...report.metrics.map((m) => _buildMetricTile(m)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(HealthMetric metric) {
    String valueStr;
    switch (metric.type) {
      case HealthMetricType.memoryUsageBytes:
      case HealthMetricType.peakMemoryBytes:
      case HealthMetricType.cachedImageBytes:
        final mb = metric.value / (1024 * 1024);
        valueStr = '${mb.toStringAsFixed(1)} MB';
        break;
      default:
        valueStr = '${metric.value}';
    }

    return ListTile(
      dense: true,
      title: Text(metric.type.label),
      trailing: Text(
        valueStr,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildVerificationCard(ReleaseVerificationReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  report.allPassed
                      ? Icons.verified_user
                      : Icons.shield,
                  color: report.allPassed ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'Release Verification',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: report.allPassed
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${report.passedCount}/${report.totalChecks} PASSED',
                    style: TextStyle(
                      color: report.allPassed ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatRow('Version', '${report.appVersion} (#${report.buildNumber})'),
            _buildStatRow('Profile', report.buildProfile),
            const Divider(),
            ...report.records.map((r) => _buildVerificationTile(r)),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationTile(VerificationRecord record) {
    return ListTile(
      leading: Icon(
        record.result == VerificationResult.passed
            ? Icons.check_circle
            : record.result == VerificationResult.failed
                ? Icons.error
                : Icons.hourglass_empty,
        color: record.result == VerificationResult.passed
            ? Colors.green
            : record.result == VerificationResult.failed
                ? Colors.red
                : Colors.grey,
      ),
      title: Text(record.check.label),
      subtitle: Text(record.description),
      trailing: Text(
        record.result == VerificationResult.passed ? 'PASS' : 'FAIL',
        style: TextStyle(
          color: record.result == VerificationResult.passed
              ? Colors.green
              : Colors.red,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      color: Colors.red.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rocket_launch, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No deployment data yet.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Configure a build profile to get started.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
