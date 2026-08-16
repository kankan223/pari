import 'dart:async';

import 'package:flutter/material.dart';

import '../../geo/domain/explore_radius.dart';
import '../domain/ledger_geo_bloc.dart';
import '../domain/ledger_geo_state.dart';
import 'ledger_theme.dart';

/// The Explore Nearby radius control (DESIGN.md §5.2, Task 7.2).
///
/// A bottom sheet listing the coarse radius options (`Local only` / 5 km /
/// 10 km / 25 km) plus the current scope line and a `Use my location`
/// re-resolve action. Choosing a radius narrows/broadens the feed scope.
///
/// SECURITY CHECKPOINT (Task 7.2): the sheet renders ONLY the coarse
/// scope line (`District · Locality · 800001`) and radius labels — never
/// coordinates, addresses, or any fingerprintable location detail.
class ExploreNearbySheet extends StatefulWidget {
  const ExploreNearbySheet({
    super.key,
    required this.bloc,
    required this.state,
  });

  final LedgerGeoBloc bloc;
  final LedgerGeoState state;

  @override
  State<ExploreNearbySheet> createState() => _ExploreNearbySheetState();
}

class _ExploreNearbySheetState extends State<ExploreNearbySheet> {
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EXPLORE NEARBY',
              style: TextStyle(
                color: LedgerTheme.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'serif',
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              state.place?.scopeLine ?? 'Choose your civic scope',
              style: const TextStyle(color: LedgerTheme.muted, fontSize: 12),
            ),
            const Divider(height: 24, color: LedgerTheme.divider),
            for (final radius in ExploreRadius.values) ...[
              _RadiusTile(
                radius: radius,
                selected: state.radius == radius,
                onTap: () async {
                  await widget.bloc.setRadius(radius);
                  if (context.mounted) {
                    Navigator.of(context).pop(radius);
                  }
                },
              ),
              const SizedBox(height: 4),
            ],
            const Divider(height: 20, color: LedgerTheme.divider),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_resubscribe()),
                    icon: const Icon(Icons.my_location_rounded, size: 16),
                    label: const Text('Use my location'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: LedgerTheme.ledgerGreen,
                      side: const BorderSide(color: LedgerTheme.ledgerGreen),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resubscribe() async {
    await widget.bloc.retryResolve();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _RadiusTile extends StatelessWidget {
  const _RadiusTile({
    required this.radius,
    required this.selected,
    required this.onTap,
  });

  final ExploreRadius radius;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:
              selected ? LedgerTheme.ledgerGreen.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(6),
          border: selected
              ? Border.all(color: LedgerTheme.ledgerGreen, width: 1)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              radius.isExpanded ? Icons.radar_rounded : Icons.home_rounded,
              size: 18,
              color: selected ? LedgerTheme.ledgerGreen : LedgerTheme.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    radius.label,
                    style: TextStyle(
                      color: LedgerTheme.ink,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  Text(
                    radius.detail,
                    style: const TextStyle(
                      color: LedgerTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded,
                  size: 18, color: LedgerTheme.ledgerGreen),
          ],
        ),
      ),
    );
  }
}
