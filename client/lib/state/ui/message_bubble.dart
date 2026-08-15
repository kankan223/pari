import 'package:flutter/material.dart';

import '../domain/message_side.dart';
import '../domain/message_state.dart';
import 'vault_theme.dart';

/// A single Vault message bubble (DESIGN.md §6.3).
///
/// - **Received:** surface white, left-aligned, Vault Blue 3dp left bar.
/// - **Sent:** Vault Blue background, right-aligned, white text.
/// - Body: the DECRYPTED message content ([MessageSummary.content], Task
///   6.3) or the fixed "[end-to-end encrypted]" placeholder when the message
///   cannot be decrypted (no session / tampered MAC — fallback never leaks).
/// - Delivery receipts: ✓ (sent, not yet delivered) / ✓✓ (delivered).
/// - Queued indicator: an amber "⏳ Sending when online" line under a sent
///   message that has not been delivered yet (DESIGN §6.3).
///
/// SECURITY CHECKPOINT (Task 6.1/6.3): the bubble renders ONLY
/// [MessageSummary.content] (decrypted by the BLoC, never raw ciphertext)
/// and delivery flags ([delivered], [expiresAt]) — no identifiers, no raw
/// payloads.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.side,
  });

  final MessageSummary message;
  final MessageSide side;

  bool get _isSent => side == MessageSide.sent;

  @override
  Widget build(BuildContext context) {
    final isSent = _isSent;
    final delivered = message.delivered;
    final showQueued = isSent && !delivered;

    final bubble = _BubbleBody(
      isSent: isSent,
      delivered: delivered,
      expiresAt: message.expiresAt,
      content: message.content,
    );

    final content = showQueued
        ? Column(
            crossAxisAlignment:
                isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              bubble,
              const SizedBox(height: 3),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_top_rounded,
                      size: 12, color: Colors.amber),
                  SizedBox(width: 4),
                  Text(
                    'Sending when online',
                    style: TextStyle(fontSize: 10, color: Colors.amber),
                  ),
                ],
              ),
            ],
          )
        : bubble;

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: content,
    );
  }
}

/// The bubble body: the received variant composes a 3dp Vault Blue left bar
/// NEXT TO a rounded white panel (a rounded `Border` with a non-uniform
/// colored side is not paint-able — Flutter forbids `borderRadius` on
/// non-uniform `Border`), the sent variant is a single Vault Blue rounded
/// panel.
class _BubbleBody extends StatelessWidget {
  const _BubbleBody({
    required this.isSent,
    required this.delivered,
    this.expiresAt,
    this.content,
  });

  final bool isSent;
  final bool delivered;
  final DateTime? expiresAt;

  /// Decrypted message body; null → the fixed placeholder is shown.
  final String? content;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isSent ? VaultTheme.vaultBlue : Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: isSent ? null : Border.all(color: Colors.black12, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_rounded,
                size: 12,
                color: isSent ? Colors.white70 : Colors.black38,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: content == null
                    ? Text(
                        '[end-to-end encrypted]',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isSent ? Colors.white70 : Colors.black54,
                        ),
                      )
                    : Text(
                        content!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isSent ? Colors.white : Colors.black87,
                        ),
                      ),
              ),
            ],
          ),
          if (expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Expires',
              style: TextStyle(
                fontSize: 10,
                color: isSent ? Colors.white60 : Colors.black45,
              ),
            ),
          ],
          if (isSent) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  delivered ? '✓✓' : '✓',
                  style: TextStyle(
                    fontSize: 11,
                    color: isSent ? Colors.white70 : Colors.black45,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  delivered ? 'delivered' : 'sent',
                  style: TextStyle(
                    fontSize: 10,
                    color: isSent ? Colors.white60 : Colors.black45,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (isSent) {
      return panel;
    }
    // Received: 3dp Vault Blue left bar beside the rounded white panel.
    // IntrinsicHeight lets the bar span the panel's full height inside the
    // unbounded ListView (CrossAxisAlignment.stretch would demand an
    // infinite height here).
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 3, color: VaultTheme.vaultBlue),
          panel,
        ],
      ),
    );
  }
}
