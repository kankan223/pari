import 'package:flutter/material.dart';

import '../../rate_limit/domain/rate_limit_policy.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/rate_limit_bloc.dart';
import '../domain/rate_limit_state.dart';

/// Rate Limiting & Abuse Prevention screen (Task 11.3).
///
/// Displays per-policy rate limit status (request counts, cooldown
/// indicators) and recent abuse detection events.
///
/// SECURITY CHECKPOINT (11.3): the screen is wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE) to prevent screenshots.
/// It renders ONLY fixed policy labels, trigger labels, severity
/// labels, and integer counts — never identity, never PII.
class RateLimitScreen extends StatefulWidget {
  final RateLimitBloc bloc;

  const RateLimitScreen({super.key, required this.bloc});

  @override
  State<RateLimitScreen> createState() => _RateLimitScreenState();
}

class _RateLimitScreenState extends State<RateLimitScreen> {
  @override
  void initState() {
    super.initState();
    widget.bloc.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreenWrapper(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('RATE LIMITS'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => widget.bloc.refresh(),
            ),
          ],
        ),
        body: StreamBuilder<RateLimitState>(
          stream: widget.bloc.state,
          initialData: widget.bloc.current,
          builder: (context, snapshot) {
            final state = snapshot.data ?? const RateLimitState();

            if (state.phase == RateLimitPhase.loading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.phase == RateLimitPhase.error) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      state.errorMessage ?? 'Unknown error',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => widget.bloc.refresh(),
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              );
            }

            return _RateLimitContent(state: state);
          },
        ),
      ),
    );
  }
}

class _RateLimitContent extends StatelessWidget {
  final RateLimitState state;

  const _RateLimitContent({required this.state});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⟡ RATE LIMITS & ABUSE PREVENTION',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 8),
                if (state.anyCooldownActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber,
                            size: 16, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('COOLDOWN ACTIVE',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Policy buckets
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'POLICY STATUS',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final policy = RateLimitPolicy.values[index];
              final bucket = state.bucketFor(policy.name);
              return _PolicyTile(policy: policy, bucket: bucket);
            },
            childCount: RateLimitPolicy.values.length,
          ),
        ),

        // Abuse events
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'ABUSE DETECTION',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
            ),
          ),
        ),
        if (state.abuseEvents.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No abuse events detected.',
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final event = state.abuseEvents[index];
                return _AbuseEventTile(event: event);
              },
              childCount: state.abuseEvents.length,
            ),
          ),
      ],
    );
  }
}

class _PolicyTile extends StatelessWidget {
  final RateLimitPolicy policy;
  final dynamic bucket;

  const _PolicyTile({required this.policy, this.bucket});

  @override
  Widget build(BuildContext context) {
    final isActive = bucket != null && bucket.cooldownActive;
    final remaining = bucket?.remainingRequests ?? policy.maxRequests;
    final progress =
        bucket != null ? bucket.requestCount / policy.maxRequests : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isActive ? Colors.red.shade50 : null,
      child: ListTile(
        leading: Icon(
          isActive ? Icons.block : Icons.check_circle_outline,
          color: isActive ? Colors.red : Colors.green,
        ),
        title: Text(policy.label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isActive ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$remaining / ${policy.maxRequests} remaining · '
              '${policy.windowSeconds}s window',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (isActive)
              Text(
                'COOLDOWN: ${bucket.cooldownRemainingSeconds(DateTime.now().toUtc())}s remaining',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
              ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _AbuseEventTile extends StatelessWidget {
  final dynamic event;

  const _AbuseEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor(event.trigger.severity);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(Icons.report_problem, color: severityColor),
        title: Text(event.trigger.label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    event.trigger.severity.shortLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: severityColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${event.occurrenceCount} occurrences',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  Color _severityColor(dynamic severity) {
    switch (severity.name) {
      case 'critical':
        return Colors.red.shade900;
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
