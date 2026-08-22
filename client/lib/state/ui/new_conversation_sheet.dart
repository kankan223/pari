import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/user_search_bloc.dart';
import '../domain/user_search_state.dart';
import '../domain/peer_handle.dart';
import 'vault_theme.dart';

/// Bottom sheet for searching users and starting a new conversation.
///
/// Shows a search field, real-time results from the [UserSearchBloc],
/// and a "Start Conversation" action when a user is found.
///
/// SECURITY CHECKPOINT: the sheet renders ONLY the public username and
/// a derived non-PII handle ([formatPeerHandle]). The raw blind hash
/// is NEVER shown in the UI tree.
class NewConversationSheet extends StatefulWidget {
  final UserSearchBloc searchBloc;
  final ValueChanged<String> onStartConversation;

  const NewConversationSheet({
    super.key,
    required this.searchBloc,
    required this.onStartConversation,
  });

  @override
  State<NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<NewConversationSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  StreamSubscription<UserSearchState>? _sub;
  UserSearchState? _searchState;

  @override
  void initState() {
    super.initState();
    _sub = widget.searchBloc.state.listen((state) {
      if (mounted) setState(() => _searchState = state);
    });
    // Auto-focus the search field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _search() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    widget.searchBloc.search(query);
  }

  void _startConversation(String blindHashId) {
    widget.onStartConversation(blindHashId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title.
              Text(
                'NEW CONVERSATION',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: VaultTheme.vaultBlue,
                ),
              ),
              const SizedBox(height: 12),

              // Search field.
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Search by username...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _controller.clear();
                            widget.searchBloc.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              // Search results.
              _buildResults(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme) {
    final state = _searchState;

    if (state == null || state.isIdle) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Type a username to find someone to message',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
        ),
      );
    }

    if (state.isSearching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (state.isNotFound) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F0E8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'No user found with that username.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    if (state.isError) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Search failed. Please try again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.red[700]),
        ),
      );
    }

    if (state.isFound && state.result != null) {
      final result = state.result!;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: VaultTheme.vaultBlue.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            // User info.
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: VaultTheme.vaultBlue,
                  child: Text(
                    result.username[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${result.username}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: VaultTheme.vaultBlue,
                        ),
                      ),
                      Text(
                        formatPeerHandle(result.blindHashId),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontFamily: VaultTheme.monoFont,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Start conversation button.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _startConversation(result.blindHashId),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('Start Conversation'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: VaultTheme.vaultBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
