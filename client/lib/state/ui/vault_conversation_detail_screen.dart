import 'dart:async';

import 'package:flutter/material.dart';

import '../../security/domain/root_detection_service.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/message_bloc.dart';
import '../domain/message_side.dart';
import '../domain/message_state.dart';
import '../domain/peer_handle.dart';
import 'conversation_composer.dart';
import 'message_bubble.dart';
import 'vault_theme.dart';

/// The Vault conversation detail screen (DESIGN.md §6.3).
///
/// Consumes the [MessageBloc] state stream ONLY (clean architecture). Renders
/// a simplified header (back, display handle, 🔒 E2EE badge) above the
/// message thread of [MessageBubble]s, and the interactive
/// [ConversationComposer] wired to [MessageBloc.send] (Task 6.3).
///
/// SECURITY CHECKPOINT (Task 6.1/6.3): the screen is wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE). The peer is rendered only through
/// [formatPeerHandle]; bubbles render DECRYPTED message content from the
/// BLoC state (never raw ciphertext), with the fixed "[end-to-end
/// encrypted]" placeholder as the fallback when a message cannot be
/// decrypted — no identifiers, no raw payloads.
class VaultConversationDetailScreen extends StatefulWidget {
  const VaultConversationDetailScreen({
    super.key,
    required this.bloc,
    required this.participantHash,
    this.onBack,
    this.sideResolver = defaultMessageSide,
    this.secureFlagService,
    this.rootDetectionService,
  });

  final MessageBloc bloc;

  /// The peer's 64-hex blind participant hash (rendered only via
  /// [formatPeerHandle]).
  final String participantHash;

  /// Pops back to the conversation list.
  final VoidCallback? onBack;

  /// Maps each message to its bubble side (default: delivered → received).
  final MessageSideResolver sideResolver;

  final SecureFlagService? secureFlagService;
  final RootDetectionService? rootDetectionService;

  @override
  State<VaultConversationDetailScreen> createState() =>
      _VaultConversationDetailScreenState();
}

class _VaultConversationDetailScreenState
    extends State<VaultConversationDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Broadcast state stream, no replay: if the composition root started the
    // bloc before this widget subscribed, the first emission would be lost
    // and the thread would show a permanent loader. refresh() recomputes now
    // (same late-subscribe treatment as SyncStatusBar, Task 5.4).
    unawaited(widget.bloc.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = widget.bloc;
    final participantHash = widget.participantHash;
    final onBack = widget.onBack;
    final sideResolver = widget.sideResolver;
    return _secure(
      Scaffold(
        body: Column(
          children: [
            // Simplified header (DESIGN §6.3): back · handle · 🔒 E2EE.
            SafeArea(
              bottom: false,
              child: Container(
                color: VaultTheme.vaultBlue,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    if (onBack != null)
                      IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        tooltip: 'Back',
                      ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        formatPeerHandle(participantHash),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontFamily: VaultTheme.monoFont,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Tooltip(
                      message: 'End-to-end encrypted',
                      child: Icon(Icons.lock_rounded,
                          color: Colors.white70, size: 18),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<MessageState>(
                stream: bloc.state,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  if (state == null || !state.hasLoaded) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  final messages = state.messages;
                  if (messages.isEmpty) {
                    return const Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(color: Colors.black45),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final summary = messages[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: MessageBubble(
                          message: summary,
                          side: sideResolver(summary),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // Interactive composer (Task 6.3): sends encrypt via the BLoC's
            // MessageCipher and persist locally (offline-first). If sending
            // fails (e.g. no established key-exchange session), the error is
            // swallowed — never an unhandled async exception, never a crash.
            ConversationComposer(
              onSend: (text) => unawaited(_send(bloc, text)),
            ),
          ],
        ),
      ),
    );
  }

  /// Sends [text] through [bloc], swallowing failures (no session yet,
  /// encryption error) so the composer never surfaces an unhandled async
  /// exception. A future task can surface a transient "session required"
  /// hint; the send itself is best-effort like every other local-first write.
  Future<void> _send(MessageBloc bloc, String text) async {
    try {
      await bloc.send(text);
    } catch (_) {
      // Intentionally ignored: never leak error detail toward the UI.
    }
  }

  /// Wraps in [SecureScreenWrapper], defaulting to the production FLAG_SECURE
  /// service when the test seam is not injected.
  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    final rootDetectionService = widget.rootDetectionService;
    return flag == null
        ? SecureScreenWrapper(
            rootDetectionService: rootDetectionService, child: child)
        : SecureScreenWrapper(
            secureFlagService: flag,
            rootDetectionService: rootDetectionService,
            child: child,
          );
  }
}
