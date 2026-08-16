import 'package:flutter/material.dart';

import '../../ledger/domain/ledger_category.dart';
import 'ledger_theme.dart';

/// Ledger category tag (DESIGN.md §4.4).
///
/// A compact pill: `# CIVIC INFRA` in the category's pillar accent at 12%
/// background opacity, 1dp accent border, 4dp radius. The accent color is
/// derived from [LedgerCategory] via [LedgerTheme.categoryColor].
///
/// SECURITY CHECKPOINT (Task 7.1): renders ONLY the fixed category label —
/// never user content, never identity.
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.category,
    this.selected = false,
    this.onTap,
  });

  final LedgerCategory category;

  /// When true, the chip is rendered as the active filter (filled accent).
  final bool selected;

  /// Tap handler for the feed filter chips. When null the chip is static
  /// (post cards).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = LedgerTheme.categoryColor(category);
    final background = selected ? accent : accent.withValues(alpha: 0.12);
    final foreground = selected ? Colors.white : accent;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent, width: 1),
      ),
      child: Text(
        category.label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          fontFamily: 'NotoSans',
        ),
      ),
    );
    if (onTap == null) {
      return chip;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: chip,
    );
  }
}
