import 'package:flutter/material.dart';

import 'vault_theme.dart';

/// Shows a popup menu of emoji reactions when long-pressing a message.
/// Returns the selected emoji, or null if dismissed.
class EmojiReactionPicker extends StatefulWidget {
  final ValueChanged<String> onReact;
  final Offset position;

  const EmojiReactionPicker({
    super.key,
    required this.onReact,
    required this.position,
  });

  /// Common reaction emojis used across the app.
  static const defaultEmojis = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
    '🔥',
    '👏',
    '💯',
    '✅',
    '🎉',
    '💪',
  ];

  /// Shows the picker as an overlay at the given position.
  static Future<void> show(
    BuildContext context, {
    required Offset position,
    required ValueChanged<String> onReact,
  }) async {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _EmojiOverlay(
        position: position,
        onReact: (emoji) {
          entry.remove();
          onReact(emoji);
        },
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<EmojiReactionPicker> createState() => _EmojiReactionPickerState();
}

class _EmojiReactionPickerState extends State<EmojiReactionPicker> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: VaultTheme.vaultCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: EmojiReactionPicker.defaultEmojis.map((emoji) {
          return GestureDetector(
            onTap: () => widget.onReact(emoji),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 24),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Overlay entry for the emoji picker.
class _EmojiOverlay extends StatelessWidget {
  final Offset position;
  final ValueChanged<String> onReact;
  final VoidCallback onDismiss;

  const _EmojiOverlay({
    required this.position,
    required this.onReact,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Tap outside to dismiss
        GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.translucent,
          child: Container(
            color: Colors.black.withValues(alpha: 0.1),
          ),
        ),
        // Emoji picker positioned above the message
        Positioned(
          left: position.dx.clamp(16.0, MediaQuery.of(context).size.width - 320),
          top: (position.dy - 60).clamp(0.0, position.dy - 60),
          child: Material(
            color: Colors.transparent,
            child: EmojiReactionPicker(
              onReact: onReact,
              position: position,
            ),
          ),
        ),
      ],
    );
  }
}

/// Displays emoji reactions on a message bubble.
class MessageReactions extends StatelessWidget {
  final Map<String, int> reactions;
  final ValueChanged<String>? onReact;

  const MessageReactions({
    super.key,
    required this.reactions,
    this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: reactions.entries.map((entry) {
        return GestureDetector(
          onTap: () => onReact?.call(entry.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: VaultTheme.vaultBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: VaultTheme.vaultBlue.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 2),
                Text(
                  '${entry.value}',
                  style: TextStyle(
                    color: VaultTheme.vaultBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
