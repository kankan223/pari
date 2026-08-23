import 'message_search_result.dart';

/// Repository for searching through message history.
abstract class MessageSearchRepository {
  /// Search messages across all conversations or within a specific one.
  ///
  /// [query] is the search text (case-insensitive substring match).
  /// [conversationId] optionally narrows to a single conversation.
  /// [limit] and [offset] control pagination.
  Future<MessageSearchResults> search({
    required String query,
    String? conversationId,
    int limit = 20,
    int offset = 0,
  });

  /// Get recent messages across all conversations for quick access.
  Future<List<MessageSearchResult>> recentMessages({int limit = 50});
}
