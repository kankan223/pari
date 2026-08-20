import 'package:flutter/material.dart';

import '../../performance/domain/startup_optimizer.dart';
import '../domain/performance_bloc.dart';
import '../domain/performance_state.dart';
import '../../security/ui/secure_screen_wrapper.dart';

/// Performance monitoring screen (Task 12.1).
///
/// Displays cold/warm start times, memory usage, image cache stats,
/// and deferred pillar loading states. Wrapped in SecureScreenWrapper
/// (FLAG_SECURE) per project security requirements.
class PerformanceMonitorScreen extends StatefulWidget {
  final PerformanceBloc bloc;

  const PerformanceMonitorScreen({super.key, required this.bloc});

  @override
  State<PerformanceMonitorScreen> createState() =>
      _PerformanceMonitorScreenState();
}

class _PerformanceMonitorScreenState extends State<PerformanceMonitorScreen> {
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
  void dispose() {
    // Don't close the bloc here — it's owned by the harness
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreenWrapper(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PERFORMANCE MONITOR'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => widget.bloc.refresh(),
              tooltip: 'Refresh metrics',
            ),
          ],
        ),
        body: StreamBuilder<PerformanceState>(
          stream: widget.bloc.state,
          initialData: widget.bloc.current,
          builder: (context, snapshot) {
            final state = snapshot.data ?? const PerformanceState();
            return _buildBody(state);
          },
        ),
      ),
    );
  }

  Widget _buildBody(PerformanceState state) {
    if (state.phase == PerformancePhase.measuring) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Startup time section
        _buildSectionHeader('STARTUP TIMES'),
        _buildMetricCard(
          label: 'COLD START',
          value: state.metrics.coldStartMs > 0
              ? '${state.metrics.coldStartMs}ms'
              : 'Not measured',
          isGood: state.coldStartTargetMet,
          target: '<600ms',
        ),
        _buildMetricCard(
          label: 'WARM START',
          value: state.metrics.warmStartMs > 0
              ? '${state.metrics.warmStartMs}ms'
              : 'Not measured',
        ),
        const SizedBox(height: 16),

        // Memory section
        _buildSectionHeader('MEMORY USAGE'),
        _buildMetricCard(
          label: 'CURRENT',
          value: '${state.metrics.memoryUsageMB.toStringAsFixed(1)} MB',
        ),
        _buildMetricCard(
          label: 'PEAK',
          value: '${state.metrics.peakMemoryMB.toStringAsFixed(1)} MB',
        ),
        const SizedBox(height: 16),

        // Image cache section
        _buildSectionHeader('IMAGE CACHE'),
        _buildMetricCard(
          label: 'CACHED IMAGES',
          value: '${state.metrics.cachedImageCount}',
        ),
        _buildMetricCard(
          label: 'CACHE SIZE',
          value:
              '${(state.metrics.cachedImageBytes / 1024).toStringAsFixed(0)} KB',
        ),
        const SizedBox(height: 16),

        // Lazy loading section
        _buildSectionHeader('LAZY LOADING'),
        _buildMetricCard(
          label: 'LAZY-LOADED ITEMS',
          value: '${state.metrics.lazyLoadedCount}',
        ),
        const SizedBox(height: 16),

        // Deferred pillars section
        _buildSectionHeader('DEFERRED PILLARS'),
        _buildMetricCard(
          label: 'READY',
          value: '${state.readyPillarCount}/${state.deferredPillars.length}',
        ),
        if (state.loadingPillarCount > 0)
          _buildMetricCard(
            label: 'LOADING',
            value: '${state.loadingPillarCount}',
            isWarning: true,
          ),
        ...state.deferredPillars.map(_buildPillarTile),

        if (state.errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildErrorBanner(state.errorMessage!),
        ],
      ],
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

  Widget _buildPillarTile(DeferredPillar pillar) {
    IconData icon;
    Color color;

    switch (pillar.state) {
      case DeferredPillarState.notStarted:
        icon = Icons.radio_button_unchecked;
        color = Colors.grey;
        break;
      case DeferredPillarState.loading:
        icon = Icons.hourglass_top;
        color = Colors.orange;
        break;
      case DeferredPillarState.ready:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case DeferredPillarState.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
    }

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(pillar.displayName),
      subtitle: Text(
        pillar.state.name.toUpperCase(),
        style: TextStyle(fontSize: 12, color: color),
      ),
      trailing: pillar.loadDurationMs != null
          ? Text(
              '${pillar.loadDurationMs}ms',
              style: const TextStyle(fontSize: 12),
            )
          : null,
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
}
