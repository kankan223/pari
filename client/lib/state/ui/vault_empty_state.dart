import 'package:flutter/material.dart';

/// The Vault's empty conversation state (DESIGN.md §6.2).
///
/// Shared by the REAL conversation list (no conversations yet) AND the
/// DECOY vault screen (Task 6.6) so a duress-unlocked decoy is visually
/// indistinguishable from a real, freshly-registered vault: identical
/// icon, identical fixed copy, identical layout. No user data ever appears
/// here — the copy is fixed and PII-free.
class VaultEmptyState extends StatelessWidget {
  const VaultEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 40, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            'No conversations yet',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Your end-to-end encrypted conversations will appear here.',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
