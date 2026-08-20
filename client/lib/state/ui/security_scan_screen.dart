import 'package:flutter/material.dart';

import '../../security/domain/penetration_test_scenario.dart';
import '../../security/domain/vulnerability_severity.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/security_scan_bloc.dart';
import '../domain/security_scan_state.dart';

/// UI screen for automated security scanning (Task 13.4).
///
/// Displays security scan results, vulnerability findings, and penetration
/// test results. Wrapped in SecureScreenWrapper for FLAG_SECURE protection.
///
/// Security contract:
/// - All displayed data is scan metadata only — zero PII.
/// - Findings show file paths and line numbers, never user content.
/// - FLAG_SECURE prevents screenshots of security scan results.
class SecurityScanScreen extends StatelessWidget {
  final SecurityScanBloc bloc;

  const SecurityScanScreen({super.key, required this.bloc});

  @override
  Widget build(BuildContext context) {
    return SecureScreenWrapper(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Security Scanner'),
          actions: [
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Run Scan',
              onPressed: () => bloc.startScan(),
            ),
            IconButton(
              icon: const Icon(Icons.security),
              tooltip: 'Run Penetration Tests',
              onPressed: () => bloc.runPenetrationTests(),
            ),
          ],
        ),
        body: StreamBuilder<SecurityScanState>(
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

  Widget _buildBody(BuildContext context, SecurityScanState state) {
    if (state.isScanning) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning codebase for vulnerabilities...'),
          ],
        ),
      );
    }

    if (state.isRunningPentests) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Running penetration tests...'),
          ],
        ),
      );
    }

    if (state.status == SecurityScanStatus.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(state.errorMessage ?? 'Unknown error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => bloc.refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Scan Summary
        if (state.lastScanResult != null) ...[
          _buildScanSummary(state),
          const SizedBox(height: 16),
        ],

        // Findings
        if (state.lastScanResult?.hasFindings ?? false) ...[
          _buildFindingsSection(state),
          const SizedBox(height: 16),
        ],

        // Penetration Tests
        if (state.pentestResults.isNotEmpty) ...[
          _buildPentestSection(state),
          const SizedBox(height: 16),
        ],

        // Empty State
        if (state.lastScanResult == null && state.pentestResults.isEmpty)
          _buildEmptyState(),
      ],
    );
  }

  Widget _buildScanSummary(SecurityScanState state) {
    final result = state.lastScanResult!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.passed ? Icons.check_circle : Icons.warning,
                  color: result.passed ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  result.passed ? 'SCAN PASSED' : 'ISSUES FOUND',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatRow('Files Scanned', '${result.filesScanned}'),
            _buildStatRow('Lines Analyzed', '${result.linesAnalyzed}'),
            _buildStatRow('Duration', '${result.durationMs}ms'),
            _buildStatRow('Risk Score', '${result.riskScore}'),
            const Divider(),
            _buildSeverityRow(
              'Critical',
              result.criticalCount,
              VulnerabilitySeverity.critical,
            ),
            _buildSeverityRow(
              'High',
              result.highCount,
              VulnerabilitySeverity.high,
            ),
            _buildSeverityRow(
              'Medium',
              result.mediumCount,
              VulnerabilitySeverity.medium,
            ),
            _buildSeverityRow(
              'Low',
              result.lowCount,
              VulnerabilitySeverity.low,
            ),
            _buildSeverityRow(
              'Info',
              result.informationalCount,
              VulnerabilitySeverity.informational,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFindingsSection(SecurityScanState state) {
    final findings = state.lastScanResult!.findings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vulnerability Findings',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...findings.map((finding) => _buildFindingTile(finding)),
          ],
        ),
      ),
    );
  }

  Widget _buildFindingTile(dynamic finding) {
    final color = _severityColor(finding.severity);
    return ListTile(
      leading: Icon(Icons.bug_report, color: color),
      title: Text(finding.description),
      subtitle: Text('${finding.filePath}:${finding.lineNumber}'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          finding.severity.label,
          style: TextStyle(color: color, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildPentestSection(SecurityScanState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Penetration Tests',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: state.allPentestsPassed
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${state.pentestsResisted}/${state.pentestResults.length} PASSED',
                    style: TextStyle(
                      color: state.allPentestsPassed ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...state.pentestResults.map((result) => _buildPentestTile(result)),
          ],
        ),
      ),
    );
  }

  Widget _buildPentestTile(PenetrationTestResult result) {
    return ListTile(
      leading: Icon(
        result.resisted ? Icons.shield : Icons.warning,
        color: result.resisted ? Colors.green : Colors.red,
      ),
      title: Text(result.type.label),
      subtitle: Text(result.description),
      trailing: Text(
        result.resisted ? 'PASS' : 'FAIL',
        style: TextStyle(
          color: result.resisted ? Colors.green : Colors.red,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.security, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No scans have been run yet.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Tap the play button to start a security scan.',
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

  Widget _buildSeverityRow(
    String label,
    int count,
    VulnerabilitySeverity severity,
  ) {
    final color = _severityColor(severity);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(VulnerabilitySeverity severity) {
    switch (severity) {
      case VulnerabilitySeverity.critical:
        return Colors.red;
      case VulnerabilitySeverity.high:
        return Colors.orange;
      case VulnerabilitySeverity.medium:
        return Colors.amber;
      case VulnerabilitySeverity.low:
        return Colors.blue;
      case VulnerabilitySeverity.informational:
        return Colors.grey;
    }
  }
}
