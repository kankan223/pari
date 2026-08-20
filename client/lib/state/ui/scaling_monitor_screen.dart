import 'package:flutter/material.dart';

import '../../scaling/domain/load_test_scenario.dart';
import '../domain/scaling_bloc.dart';
import '../domain/scaling_state.dart';
import '../../security/ui/secure_screen_wrapper.dart';

/// Horizontal scaling monitor screen (Task 12.4).
///
/// Displays concurrent connections, throughput, latency, and shard health.
/// Allows running load test scenarios. Wrapped in SecureScreenWrapper
/// (FLAG_SECURE) per project security requirements.
class ScalingMonitorScreen extends StatefulWidget {
  final ScalingBloc bloc;

  const ScalingMonitorScreen({super.key, required this.bloc});

  @override
  State<ScalingMonitorScreen> createState() => _ScalingMonitorScreenState();
}

class _ScalingMonitorScreenState extends State<ScalingMonitorScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.bloc.startMeasuring();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreenWrapper(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SCALING MONITOR'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => widget.bloc.refresh(),
              tooltip: 'Refresh metrics',
            ),
          ],
        ),
        body: StreamBuilder<ScalingState>(
          stream: widget.bloc.state,
          initialData: widget.bloc.current,
          builder: (context, snapshot) {
            final state = snapshot.data ?? const ScalingState();
            return _buildBody(state);
          },
        ),
      ),
    );
  }

  Widget _buildBody(ScalingState state) {
    if (state.phase == ScalingPhase.running) {
      return _buildRunningState(state);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Concurrency section
        _buildSectionHeader('CONCURRENCY'),
        _buildMetricCard(
          label: 'ACTIVE CONNECTIONS',
          value: '${state.metrics.activeConnections}',
        ),
        _buildMetricCard(
          label: 'PEAK CONNECTIONS',
          value: '${state.metrics.peakConnections}',
          isGood: state.concurrencyTargetMet,
          target: '10,000',
        ),
        const SizedBox(height: 16),

        // Throughput section
        _buildSectionHeader('THROUGHPUT'),
        _buildMetricCard(
          label: 'REQUESTS/SECOND',
          value: state.metrics.requestsPerSecond > 0
              ? state.metrics.requestsPerSecond.toStringAsFixed(1)
              : 'Not measured',
        ),
        _buildMetricCard(
          label: 'TOTAL REQUESTS',
          value: '${state.metrics.totalRequests}',
        ),
        _buildMetricCard(
          label: 'SUCCESS RATE',
          value: state.metrics.totalRequests > 0
              ? '${state.successRatePercent.toStringAsFixed(1)}%'
              : 'No requests',
          isGood: state.metrics.successRate > 0.99,
        ),
        const SizedBox(height: 16),

        // Latency section
        _buildSectionHeader('LATENCY'),
        _buildMetricCard(
          label: 'AVG LATENCY',
          value: state.metrics.avgLatencyMs > 0
              ? '${state.metrics.avgLatencyMs}ms'
              : 'Not measured',
          isGood: state.latencyTargetMet,
          target: '<200ms',
        ),
        _buildMetricCard(
          label: 'P95 LATENCY',
          value: state.metrics.p95LatencyMs > 0
              ? '${state.metrics.p95LatencyMs}ms'
              : 'Not measured',
        ),
        _buildMetricCard(
          label: 'P99 LATENCY',
          value: state.metrics.p99LatencyMs > 0
              ? '${state.metrics.p99LatencyMs}ms'
              : 'Not measured',
        ),
        const SizedBox(height: 16),

        // Shard health section
        _buildSectionHeader('SHARD HEALTH'),
        _buildMetricCard(
          label: 'HEALTHY SHARDS',
          value: '${state.metrics.healthyShards}/${state.metrics.totalShards}',
          isGood: state.allShardsHealthy,
        ),
        _buildMetricCard(
          label: 'AVG SHARD LOAD',
          value: state.metrics.avgShardLoad > 0
              ? '${(state.metrics.avgShardLoad * 100).toStringAsFixed(1)}%'
              : 'Not measured',
        ),
        const SizedBox(height: 16),

        // Load test scenarios
        _buildSectionHeader('LOAD TEST SCENARIOS'),
        ...state.availableScenarios.map((scenario) =>
            _buildScenarioTile(scenario, state.phase == ScalingPhase.running)),

        if (state.errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildErrorBanner(state.errorMessage!),
        ],
      ],
    );
  }

  Widget _buildRunningState(ScalingState state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Running: ${state.currentScenario?.name ?? 'Unknown'}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${state.currentScenario?.concurrentUsers ?? 0} concurrent users',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          Text(
            '${state.metrics.totalRequests} requests completed',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    bool? isGood,
    bool? isWarning,
    String? target,
  }) {
    Color? valueColor;
    if (isGood == true) valueColor = Colors.green;
    if (isGood == false) valueColor = Colors.red;
    if (isWarning == true) valueColor = Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            Row(
              children: [
                if (target != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      target,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScenarioTile(LoadTestScenario scenario, bool isRunning) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          _getScenarioIcon(scenario.pattern),
          color: _getScenarioColor(scenario.pattern),
        ),
        title: Text(scenario.name),
        subtitle: Text(
          '${scenario.concurrentUsers} users • ${scenario.requestsPerUser} req/user',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: isRunning
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => widget.bloc.runLoadTest(scenario),
              ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getScenarioIcon(LoadPattern pattern) {
    switch (pattern) {
      case LoadPattern.constant:
        return Icons.show_chart;
      case LoadPattern.rampUp:
        return Icons.trending_up;
      case LoadPattern.spike:
        return Icons.flash_on;
      case LoadPattern.wave:
        return Icons.waves;
    }
  }

  Color _getScenarioColor(LoadPattern pattern) {
    switch (pattern) {
      case LoadPattern.constant:
        return Colors.blue;
      case LoadPattern.rampUp:
        return Colors.green;
      case LoadPattern.spike:
        return Colors.orange;
      case LoadPattern.wave:
        return Colors.purple;
    }
  }
}
