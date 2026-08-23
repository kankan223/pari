import '../domain/message.dart';
import '../domain/message_search_repository.dart';
import '../domain/message_search_result.dart';

/// In-memory implementation of [MessageSearchRepository].
///
/// Searches through a shared message list. For dev/test use — production
/// would use SQLCipher FTS5 for full-text search.
class InMemoryMessageSearchRepository implements MessageSearchRepository {
  final List<Message> _messages;
  final Map<String, String> _conversationParticipants;

  InMemoryMessageSearchRepository({
    required List<Message> messages,
    Map<String, String>? conversationParticipants,
  })  : _messages = messages,
        _conversationParticipants = conversationParticipants ?? {};

  /// Set the participant hash for a conversation (for search results).
  void setParticipant(String conversationId, String participantHash) {
    _conversationParticipants[conversationId] = participantHash;
  }

  @override
  Future<MessageSearchResults> search({
    required String query,
    String? conversationId,
    int limit = 20,
    int offset = 0,
  }) async {
    if (query.trim().isEmpty) {
      return MessageSearchResults.empty;
    }

    final lowerQuery = query.toLowerCase();
    final matches = <MessageSearchResult>[];

    for (final msg in _messages) {
      // Filter by conversation if specified.
      if (conversationId != null && msg.conversationId != conversationId) {
        continue;
      }

      // Decode the message content (in dev mode, ciphertext is raw text).
      String content;
      try {
        content = String.fromCharCodes(msg.ciphertext);
      } catch (_) {
        continue;
      }

      // Case-insensitive substring search.
      final lowerContent = content.toLowerCase();
      final idx = lowerContent.indexOf(lowerQuery);
      if (idx < 0) continue;

      // Extract snippet with context.
      final start = (idx - 20).clamp(0, content.length);
      final end = (idx + query.length + 20).clamp(0, content.length);
      final snippet = '...${content.substring(start, end)}...';

      matches.add(MessageSearchResult(
        messageId: msg.id,
        conversationId: msg.conversationId,
        participantHash:
            _conversationParticipants[msg.conversationId] ?? '',
        snippet: snippet,
        matchStart: idx - start + 3, // +3 for the leading "..."
        matchEnd: idx - start + 3 + query.length,
        sentAt: DateTime.now().toUtc(), // In-memory: use now
        direction: msg.direction,
      ));
    }

    // Sort by relevance (most recent first for same query).
    matches.sort((a, b) => b.sentAt.compareTo(a.sentAt));

    final paginated = matches.skip(offset).take(limit).toList();

    return MessageSearchResults(
      query: query,
      results: paginated,
      totalCount: matches.length,
      offset: offset,
      hasMore: offset + limit < matches.length,
    );
  }

  @override
  Future<List<MessageSearchResult>> recentMessages({int limit = 50}) async {
    final sorted = List<Message>.from(_messages)
      ..sort((a, b) => b.id.compareTo(a.id)); // Rough sort by ID

    return sorted.take(limit).map((msg) {
      String content;
      try {
        content = String.fromCharCodes(msg.ciphertext);
      } catch (_) {
        content = '';
      }

      return MessageSearchResult(
        messageId: msg.id,
        conversationId: msg.conversationId,
        participantHash:
            _conversationParticipants[msg.conversationId] ?? '',
        snippet: content.length > 60
            ? '${content.substring(0, 60)}...'
            : content,
        matchStart: 0,
        matchEnd: 0,
        sentAt: DateTime.now().toUtc(),
        direction: msg.direction,
      );
    }).toList();
  }
}
