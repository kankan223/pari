import 'package:flutter/material.dart';

import 'vault_theme.dart';

/// The Vault conversation composer (DESIGN §6.3 input bar) — Task 6.3.
///
/// Replaces the static 52dp placeholder with a real, interactive composer:
/// a single-line text field and a send action (button + keyboard action).
/// It is a PURE presentational widget: the caller supplies [onSend]; the
/// composer never touches repositories, blocs, or the network.
///
/// SECURITY CHECKPOINT (Task 6.3): the composer renders NO identifiers, no
/// PII, and no payloads. The text entered here is plaintext that the caller
/// (via the message BLoC) encrypts before persistence — it is never shown
/// anywhere else on this widget.
class ConversationComposer extends StatefulWidget {
  /// Invoked with the trimmed non-empty text when the user sends.
  final ValueChanged<String> onSend;

  const ConversationComposer({super.key, required this.onSend});

  @override
  State<ConversationComposer> createState() => _ConversationComposerState();
}

class _ConversationComposerState extends State<ConversationComposer> {
  final TextEditingController _controller = TextEditingController();

  bool get _hasText => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    // Rebuild so the send button enables/disables with the field content.
    setState(() {});
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Type a message…',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                    borderSide: BorderSide(color: Colors.black12),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: _hasText ? _send : null,
              icon: const Icon(Icons.send_rounded, size: 22),
              color: _hasText ? VaultTheme.vaultBlue : Colors.black26,
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
