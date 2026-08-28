import 'package:flutter/material.dart';

import 'vault_theme.dart';

/// Community screen — combines ledger feed, categories, compose, and
/// social features into a single unified experience.
class CommunityScreen extends StatelessWidget {
  final Widget child;

  const CommunityScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

/// Category filter chips for the community feed.
class CommunityCategoryBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const CommunityCategoryBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const categories = [
    ('All', Icons.all_inclusive),
    ('Safety', Icons.shield_outlined),
    ('Environment', Icons.eco_outlined),
    ('Infrastructure', Icons.build_outlined),
    ('Governance', Icons.account_balance_outlined),
    ('Health', Icons.favorite_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, icon) = categories[i];
          final isSelected = label == selected;
          return FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14),
                const SizedBox(width: 4),
                Text(label),
              ],
            ),
            selected: isSelected,
            onSelected: (_) => onSelected(label),
            selectedColor: VaultTheme.vaultBlue.withValues(alpha: 0.15),
            checkmarkColor: VaultTheme.vaultBlue,
            labelStyle: TextStyle(
              color: isSelected ? VaultTheme.vaultBlue : VaultTheme.vaultText,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            side: BorderSide(
              color: isSelected
                  ? VaultTheme.vaultBlue.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.2),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        },
      ),
    );
  }
}
