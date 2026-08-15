import 'dart:async';

import 'package:flutter/material.dart';

import '../../security/domain/root_detection_service.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/connection_requests_bloc.dart';
import '../domain/connection_requests_state.dart';
import '../domain/conversation_bloc.dart';
import '../domain/conversation_state.dart';
import '../domain/peer_handle.dart';
import '../domain/pending_request_summary.dart';
import '../../repository/domain/username_directory.dart';
import 'vault_empty_state.dart';
import 'vault_masthead.dart';
import 'vault_pending_requests_section.dart';
import 'vault_theme.dart';

/// The Vault conversation list screen (DESIGN.md §6.2).
///
/// Consumes the [ConversationBloc] + [ConnectionRequestsBloc] state streams
/// ONLY (clean architecture — no repository/database/network access from the
/// widget tree). Renders:
/// - the [VaultMasthead] (classified aesthetic + optional new-conversation CTA),
/// - the [VaultPendingRequestsSection] (incoming connection requests, fed by
///   the [ConnectionRequestsBloc] when provided — Task 6.2 wiring),
/// - the conversation list, where EVERY preview is the fixed
///   "[end-to-end encrypted]" label — never a plaintext snippet, even on the
///   device (shoulder-surfing protection, DESIGN §6.2).
///
/// SECURITY CHECKPOINT (Task 6.1/6.2): the whole screen is wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE). Peers are rendered ONLY through
/// [formatPeerHandle] or a remembered PUBLIC username ([UsernameDirectory]) —
/// never raw blind hashes, never phone numbers.
class VaultConversationListScreen extends StatefulWidget {
  const VaultConversationListScreen({
    super.key,
    required this.bloc,
    this.requestsBloc,
    this.usernameDirectory,
    this.contextMeta,
    this.onNewConversation,
    this.onConversationTap,
    this.pendingRequests = const [],
    this.onAcceptRequest,
    this.secureFlagService,
    this.rootDetectionService,
  });

  final ConversationBloc bloc;

  /// Feeds the pending-requests queue with real inbox data (Task 6.2). When
  /// provided, the queue is driven by this BLoC and Accept calls it.
  final ConnectionRequestsBloc? requestsBloc;

  /// Resolves remembered public usernames for peer handles (Task 6.2).
  final UsernameDirectory? usernameDirectory;

  /// Local display handle shown in the masthead (must be PII-free — see
  /// [formatPeerHandle]).
  final String? contextMeta;

  /// FAB + masthead action: start a new conversation.
  final VoidCallback? onNewConversation;

  /// Opens a conversation detail screen for [conversationId].
  final ValueChanged<String>? onConversationTap;

  /// Fallback static inbox (Task 6.1 presentation tests); superseded by
  /// [requestsBloc] when provided.
  final List<PendingRequestSummary> pendingRequests;

  /// Fallback accept callback (Task 6.1); superseded by [requestsBloc].
  final ValueChanged<String>? onAcceptRequest;
  final SecureFlagService? secureFlagService;
  final RootDetectionService? rootDetectionService;

  @override
  State<VaultConversationListScreen> createState() =>
      _VaultConversationListScreenState();
}

class _VaultConversationListScreenState
    extends State<VaultConversationListScreen> {
  /// Latest inbox state pulled from [ConnectionRequestsBloc.state].
  ConnectionRequestsState? _requestsState;
  StreamSubscription<ConnectionRequestsState>? _requestsSub;

  @override
  void initState() {
    super.initState();
    // Both state streams are BROADCAST with no replay: if the composition
    // root started the blocs BEFORE this widget subscribed (the natural
    // main() → build order), the first emission would be lost. refresh()
    // recomputes now — same documented late-subscribe treatment as
    // SyncStatusBar (Task 5.4).
    unawaited(widget.bloc.refresh());
    final requestsBloc = widget.requestsBloc;
    if (requestsBloc != null) {
      unawaited(requestsBloc.refresh());
      // Subscribe ONCE here rather than via a nested StreamBuilder: a
      // builder-time subscribe can miss the pull emitted by refresh(), and
      // pulling from inside build() re-enters refresh() on every no-data
      // build (unbounded rebuild loop). Holding the latest state in a field
      // keeps the inbox live with zero build-time side effects.
      _requestsSub = requestsBloc.state.listen((state) {
        if (mounted) {
          setState(() => _requestsState = state);
        }
      });
    }
  }

  @override
  void dispose() {
    unawaited(_requestsSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloc = widget.bloc;
    final contextMeta = widget.contextMeta;
    final onNewConversation = widget.onNewConversation;
    return _secure(
      Scaffold(
        body: Column(
          children: [
            VaultMasthead(
                contextMeta: contextMeta, onAction: onNewConversation),
            Expanded(
              child: StreamBuilder<ConversationState>(
                stream: bloc.state,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  if (state == null || !state.hasLoaded) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  // Requests state is subscribed in initState (see above)
                  // and held in [_requestsState]; the static props remain
                  // the fallback when no requests BLoC is wired.
                  return _buildList(context, state, _requestsState);
                },
              ),
            ),
          ],
        ),
        floatingActionButton: onNewConversation == null
            ? null
            : FloatingActionButton(
                onPressed: onNewConversation,
                backgroundColor: VaultTheme.vaultBlue,
                tooltip: 'New conversation',
                child: const Icon(Icons.add_rounded, color: Colors.white),
              ),
      ),
    );
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

  Widget _buildList(
    BuildContext context,
    ConversationState state,
    ConnectionRequestsState? requestsState,
  ) {
    final conversations = state.conversations;
    final requestsBloc = widget.requestsBloc;
    // Task 6.2 wiring: the BLoC (when present) is the source of truth for
    // the inbox; the static props remain only as the Task 6.1 fallback.
    final List<PendingRequestSummary> pendingRequests;
    final ValueChanged<String>? onAcceptRequest;
    if (requestsBloc != null && requestsState != null) {
      pendingRequests = requestsState.pending;
      onAcceptRequest = (id) => unawaited(requestsBloc.accept(id));
    } else {
      pendingRequests = widget.pendingRequests;
      onAcceptRequest = widget.onAcceptRequest;
    }
    final onConversationTap = widget.onConversationTap;
    final showRequests = pendingRequests.isNotEmpty;
    return ListView(
      children: [
        if (showRequests)
          VaultPendingRequestsSection(
            requests: pendingRequests,
            onAccept: onAcceptRequest,
          ),
        if (showRequests) const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text(
            'CONVERSATIONS',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: VaultTheme.vaultBlue,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
          ),
        ),
        if (conversations.isEmpty)
          const VaultEmptyState()
        else
          for (final conversation in conversations)
            _ConversationTile(
              participantHash: conversation.participantHash,
              directory: widget.usernameDirectory,
              onTap: onConversationTap == null
                  ? null
                  : () => onConversationTap(conversation.id),
            ),
      ],
    );
  }
}

/// A single conversation row. The preview is ALWAYS the fixed
/// "[end-to-end encrypted]" label — ciphertext is never decoded for a
/// preview, and no plaintext snippet is ever rendered (DESIGN §6.2).
///
/// The handle shows the remembered PUBLIC username when the directory knows
/// it (Task 6.2), otherwise the derived non-PII handle.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.participantHash,
    this.directory,
    this.onTap,
  });

  final String participantHash;
  final UsernameDirectory? directory;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final directory = this.directory;
    final Widget title;
    if (directory == null) {
      title = _handleText(formatPeerHandle(participantHash), theme);
    } else {
      title = FutureBuilder<String?>(
        future: directory.usernameForHash(participantHash),
        builder: (context, snapshot) {
          final username = snapshot.data;
          final display = username != null
              ? '@$username'
              : formatPeerHandle(participantHash);
          return _handleText(display, theme);
        },
      );
    }
    return ListTile(
      leading: const Icon(Icons.lock_rounded, color: VaultTheme.vaultBlue),
      title: title,
      subtitle: const Text(
        'Preview: [end-to-end encrypted]',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Colors.black54,
        ),
      ),
      // Chevron only when the row is actually navigable.
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  Widget _handleText(String handle, ThemeData theme) => Text(
        handle,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontFamily: VaultTheme.monoFont,
          fontWeight: FontWeight.w600,
        ),
      );
}
