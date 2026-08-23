import 'package:flutter/material.dart';

import '../../repository/domain/message.dart';
import '../../repository/domain/message_search_result.dart';
import '../domain/message_search_bloc.dart';
import 'vault_theme.dart';

/// A search screen for finding messages across conversations.
///
/// Features:
/// - Real-time search with debouncing (300ms)
/// - Search within a specific conversation or globally
/// - Paginated results with "Load More"
/// - Tap result to navigate to the message in context
///
/// SECURITY CHECKPOINT: search results contain only decrypted message
/// snippets and timestamps — no raw ciphertext, no identity fields.
class MessageSearchScreen extends StatefulWidget {
  final MessageSearchBloc searchBloc;
  final String? conversationId;
  final void Function(String conversationId, String messageId)? onResultTap;

  const MessageSearchScreen({
    super.key,
    required this.searchBloc,
    this.conversationId,
    this.onResultTap,
  });

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      widget.searchBloc.loadMore();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildSearchField(),
        backgroundColor: VaultTheme.vaultBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<MessageSearchState>(
        stream: widget.searchBloc.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? widget.searchBloc.currentState;

          if (state.query.isEmpty) {
            return _buildEmptyState();
          }

          if (state.isLoading && !state.hasResults) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!state.hasResults) {
            return _buildNoResults(state.query);
          }

          return _buildResults(state);
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Search messages...',
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        border: InputBorder.none,
        prefixIcon: const Icon(Icons.search, color: Colors.white70),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.white70),
                onPressed: () {
                  _searchController.clear();
                  widget.searchBloc.clear();
                },
              )
            : null,
      ),
      onChanged: (text) {
        widget.searchBloc.query(
          text,
          conversationId: widget.conversationId,
        );
        setState(() {}); // Update clear button visibility.
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Search through your messages',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Type to find conversations, links, or keywords',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(String query) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No results for "$query"',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Try different keywords',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(MessageSearchState state) {
    final results = state.results.results;

    return Column(
      children: [
        // Results count header.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          width: double.infinity,
          color: Colors.grey[100],
          child: Text(
            '${state.totalCount} result${state.totalCount == 1 ? '' : 's'} found',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
        // Results list.
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: results.length + (state.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= results.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return _buildResultTile(results[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultTile(MessageSearchResult result) {
    final isSent = result.direction == MessageDirection.sent;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isSent
            ? VaultTheme.vaultBlue.withValues(alpha: 0.1)
            : Colors.grey[200],
        child: Icon(
          isSent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 18,
          color: isSent ? VaultTheme.vaultBlue : Colors.grey[600],
        ),
      ),
      title: Text(
        result.snippet,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '${result.conversationId} • ${_formatDate(result.sentAt)}',
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
      ),
      onTap: () {
        widget.onResultTap?.call(result.conversationId, result.messageId);
        Navigator.of(context).pop();
      },
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
