import 'package:flutter/material.dart';

import '../../repository/domain/conflict_resolution.dart';

/// Presents the outcome of a deterministic conflict resolution (Task 5.5).
///
/// When the sync engine resolves a divergent edit (local vs remote), this
/// banner tells the user WHAT happened without exposing any sensitive data:
/// only fixed labels, a deterministic status icon, and (for merged aggregates)
/// the merged numeric value. Never shows entity IDs, blind hashes, payloads,
/// or content.
///
/// This is a PURE presentational widget: it receives an already-decided
/// [ConflictResolution] and renders it. The widget tree performs no
/// repository, database, or network access (static-scanned, Task 5.5).
class ConflictResolutionBanner extends StatelessWidget {
  const ConflictResolutionBanner({
    super.key,
    required this.resolution,
    this.onTap,
  });

  /// The policy outcome to present (from the sync conflict resolver).
  final ConflictResolution resolution;

  /// Optional tap handler (e.g. to open a detail view in a future phase).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(resolution.decision);
    final theme = Theme.of(context);
    return Material(
      color: style.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(style.icon, size: 18, color: style.color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      style.title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: style.color,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    if (resolution.decision == ConflictDecision.merge &&
                        resolution.mergedValue != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Merged value: ${resolution.mergedValue}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed, non-sensitive visual identity for each conflict decision.
({String title, IconData icon, Color color}) _styleFor(
    ConflictDecision decision) {
  switch (decision) {
    case ConflictDecision.applyLocal:
      return (
        title: 'Local edit kept',
        icon: Icons.save_rounded,
        color: const Color(0xFF1565C0),
      );
    case ConflictDecision.applyRemote:
      return (
        title: 'Server version applied',
        icon: Icons.cloud_download_rounded,
        color: const Color(0xFF2E7D32),
      );
    case ConflictDecision.merge:
      return (
        title: 'Changes merged',
        icon: Icons.call_merge_rounded,
        color: const Color(0xFF6A1B9A),
      );
  }
}
