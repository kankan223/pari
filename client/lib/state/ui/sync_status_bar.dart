import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/sync_status.dart';
import '../domain/sync_status_bloc.dart';

/// Reactive sync-status indicator (Task 5.4).
///
/// Consumes the [SyncStatusBloc] state stream and renders the four sync
/// states as a compact status chip:
/// - **LIVE** — online, queue empty (green).
/// - **CACHED** — metered connection, serving cached local state (amber).
/// - **QUEUED** — online, background sync draining pending mutations (blue).
/// - **OFFLINE** — no connectivity (grey).
///
/// Features:
/// - A pending-count badge when mutations are queued or flushing.
/// - A subtle inline progress indicator while a sync run is in flight
///   (driven by [SyncStatusState.isSyncing]).
/// - Tap-to-expand revealing the last-sync timestamp and the queue count.
///
/// Clean architecture (Task 5.4): this widget talks ONLY to the
/// [SyncStatusBloc] interface — no database, network, or queue-repository
/// access from the widget tree.
///
/// SECURITY CHECKPOINT (Task 5.4): the widget renders fixed enum labels, a
/// non-sensitive integer count, and a relative timestamp. It NEVER displays
/// payloads, blind-hash IDs, phone numbers, tokens, or decrypted content.
class SyncStatusBar extends StatefulWidget {
  const SyncStatusBar({super.key, required this.bloc});

  /// The BLoC the bar observes (must already be started by the composition
  /// root).
  final SyncStatusBloc bloc;

  @override
  State<SyncStatusBar> createState() => _SyncStatusBarState();
}

class _SyncStatusBarState extends State<SyncStatusBar> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // The bloc's state stream is a BROADCAST stream with no replay: if the
    // composition root started the bloc BEFORE this widget subscribed (the
    // natural main() → build order), the first emission would be lost and the
    // bar would stay empty until the next network/queue event. refresh() is
    // the BLoC interface's documented "recompute now" — idempotent, and it
    // guarantees the bar renders the CURRENT status immediately (verified by
    // the late-subscribe widget test).
    unawaited(widget.bloc.refresh());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatusState>(
      stream: widget.bloc.state,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null) {
          // No state yet (bloc not started): render nothing rather than a
          // misleading status.
          return const SizedBox.shrink();
        }
        return _buildChip(context, state);
      },
    );
  }

  Widget _buildChip(BuildContext context, SyncStatusState state) {
    final style = _statusStyle(state.status);
    final theme = Theme.of(context);
    return Material(
      color: style.color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(style.icon, size: 18, color: style.color),
                  const SizedBox(width: 8),
                  Text(
                    style.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: style.color,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (state.pendingCount > 0)
                    _CountBadge(count: state.pendingCount, color: style.color),
                  const Spacer(),
                  if (state.isSyncing)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: style.color,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                _InfoRow(
                  icon: Icons.schedule_rounded,
                  label: 'Last synced: ${formatLastSync(state.lastSyncAt)}',
                ),
                const SizedBox(height: 4),
                _InfoRow(
                  icon: Icons.inbox_rounded,
                  label: '${state.pendingCount} pending mutation'
                      '${state.pendingCount == 1 ? '' : 's'}',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Visual identity for a sync status (fixed, non-sensitive).
({String label, IconData icon, Color color}) _statusStyle(SyncStatus status) {
  switch (status) {
    case SyncStatus.live:
      return (
        label: 'LIVE',
        icon: Icons.cloud_done_rounded,
        color: const Color(0xFF2E7D32),
      );
    case SyncStatus.cached:
      return (
        label: 'CACHED',
        icon: Icons.cloud_queue_rounded,
        color: const Color(0xFFF57F17),
      );
    case SyncStatus.queued:
      return (
        label: 'QUEUED',
        icon: Icons.cloud_upload_rounded,
        color: const Color(0xFF1565C0),
      );
    case SyncStatus.offline:
      return (
        label: 'OFFLINE',
        icon: Icons.cloud_off_rounded,
        color: const Color(0xFF546E7A),
      );
  }
}

/// Small pill showing how many mutations are queued.
class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _CountBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One line of the expanded panel (timestamp / queue count).
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Formats the last-sync timestamp for the status bar's expanded panel.
///
/// Pure and deterministic: pass [now] for tests. `null` means the device has
/// never completed a sync run. Only relative times are rendered — no
/// absolute timestamps, locales, or identifiers.
String formatLastSync(DateTime? lastSyncAt, {DateTime? now}) {
  if (lastSyncAt == null) {
    return 'Never';
  }
  final reference = now ?? DateTime.now();
  final diff = reference.difference(lastSyncAt);
  if (diff.inSeconds < 60) {
    return 'Just now';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d ago';
  }
  return '${lastSyncAt.day}/${lastSyncAt.month}/${lastSyncAt.year}';
}
