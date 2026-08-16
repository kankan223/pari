import 'package:flutter/material.dart';

import 'ledger_theme.dart';

/// The Nearby badge (dynamic-radius-ui skill step 3, Task 7.3).
///
/// Rendered on feed cards that came from the expanded dynamic-radius
/// fallback (posts outside the user's exact pin code). It clearly
/// communicates the content is outside the immediate hyperlocal zone while
/// remaining in the broadsheet visual register.
///
/// SECURITY CHECKPOINT (Task 7.3): renders ONLY the fixed `NEARBY` label
/// — no pin code, no district name, no coordinates, no identity.
class NearbyBadgeWidget extends StatelessWidget {
  const NearbyBadgeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: LedgerTheme.civicGold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: LedgerTheme.civicGold.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me_rounded, size: 11, color: LedgerTheme.civicGold),
          SizedBox(width: 3),
          Text(
            'NEARBY',
            style: TextStyle(
              color: LedgerTheme.civicGold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
