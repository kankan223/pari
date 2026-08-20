import 'package:flutter/material.dart';

import '../../cdn/domain/edge_cache_rule.dart';
import '../domain/cdn_delivery_bloc.dart';
import '../domain/cdn_delivery_state.dart';
import '../../security/ui/secure_screen_wrapper.dart';

/// CDN delivery metrics screen (Task 12.3).
///
/// Displays TTFB, bandwidth saved, cache hit ratio, and edge cache rules.
/// Wrapped in SecureScreenWrapper (FLAG_SECURE) per project security
/// requirements.
class CdnDeliveryScreen extends StatefulWidget {
  final CdnDeliveryBloc bloc;

  const CdnDeliveryScreen({super.key, required this.bloc});

  @override
  State<CdnDeliveryScreen> createState() => _CdnDeliveryScreenState();
}

class _CdnDeliveryScreenState extends State<CdnDeliveryScreen> {
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
          title: const Text('CDN DELIVERY'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => widget.bloc.refresh(),
              tooltip: 'Refresh metrics',
            ),
          ],
        ),
        body: StreamBuilder<CdnDeliveryState>(
          stream: widget.bloc.state,
          initialData: widget.bloc.current,
          builder: (context, snapshot) {
            final state = snapshot.data ?? const CdnDeliveryState();
            return _buildBody(state);
          },
        ),
      ),
    );
  }

  Widget _buildBody(CdnDeliveryState state) {
    if (state.phase == CdnDeliveryPhase.measuring) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Delivery performance section
        _buildSectionHeader('DELIVERY PERFORMANCE'),
        _buildMetricCard(
          label: 'TIME TO FIRST BYTE',
          value: state.metrics.ttfbMs > 0
              ? '${state.metrics.ttfbMs}ms'
              : 'Not measured',
        ),
        _buildMetricCard(
          label: 'AVG DOWNLOAD SPEED',
          value: state.metrics.avgDownloadSpeedBps > 0
              ? '${(state.metrics.avgDownloadSpeedBps / 1024).toStringAsFixed(1)} KB/s'
              : 'Not measured',
        ),
        const SizedBox(height: 16),

        // Bandwidth section
        _buildSectionHeader('BANDWIDTH'),
        _buildMetricCard(
          label: 'DOWNLOADED',
          value: _formatBytes(state.metrics.bytesDownloaded),
        ),
        _buildMetricCard(
          label: 'FROM CACHE',
          value: _formatBytes(state.metrics.bytesFromCache),
          isGood: state.metrics.bytesFromCache > 0,
        ),
        _buildMetricCard(
          label: 'BANDWIDTH SAVED',
          value: '${state.bandwidthSavedPercent.toStringAsFixed(1)}%',
          isGood: state.cacheHitTargetMet,
        ),
        const SizedBox(height: 16),

        // Cache performance section
        _buildSectionHeader('CACHE PERFORMANCE'),
        _buildMetricCard(
          label: 'CACHE HIT RATIO',
          value: state.metrics.totalRequests > 0
              ? '${(state.metrics.cacheHitRatio * 100).toStringAsFixed(1)}%'
              : 'No requests',
          isGood: state.cacheHitTargetMet,
          target: '>80%',
        ),
        _buildMetricCard(
          label: 'TOTAL REQUESTS',
          value: '${state.metrics.totalRequests}',
        ),
        _buildMetricCard(
          label: 'CACHE HITS',
          value: '${state.metrics.cacheHits}',
        ),
        _buildMetricCard(
          label: 'FAILED DOWNLOADS',
          value: '${state.metrics.failedDownloads}',
          isWarning: state.metrics.failedDownloads > 0,
        ),
        const SizedBox(height: 16),

        // Edge cache rules section
        _buildSectionHeader('EDGE CACHE RULES'),
        ...state.cacheRules.map(_buildCacheRuleTile),

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

  Widget _buildCacheRuleTile(EdgeCacheRule rule) {
    IconData icon;
    Color color;

    if (rule.immutable) {
      icon = Icons.lock_outline;
      color = Colors.green;
    } else if (rule.staleWhileRevalidate) {
      icon = Icons.sync;
      color = Colors.blue;
    } else {
      icon = Icons.timer_outlined;
      color = Colors.orange;
    }

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(rule.assetType),
      subtitle: Text(
        rule.cacheControl,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        _formatTtl(rule.ttlSeconds),
        style: TextStyle(fontSize: 12, color: color),
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

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _formatTtl(int seconds) {
    if (seconds >= 86400) {
      return '${seconds ~/ 86400}d';
    }
    if (seconds >= 3600) {
      return '${seconds ~/ 3600}h';
    }
    if (seconds >= 60) {
      return '${seconds ~/ 60}m';
    }
    return '${seconds}s';
  }
}
