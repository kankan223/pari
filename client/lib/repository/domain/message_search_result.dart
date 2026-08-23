import 'message.dart';

/// A single message search result with context.
class MessageSearchResult {
  final String messageId;
  final String conversationId;
  final String participantHash;

  /// The matched text snippet (highlighted in UI).
  final String snippet;

  /// Index of the match start within the original content.
  final int matchStart;

  /// Index of the match end within the original content.
  final int matchEnd;

  /// When the message was sent.
  final DateTime sentAt;

  /// Direction of the message.
  final MessageDirection direction;

  const MessageSearchResult({
    required this.messageId,
    required this.conversationId,
    required this.participantHash,
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
    required this.sentAt,
    required this.direction,
  });

  /// Get the full matched text from the snippet.
  String get matchedText => snippet.substring(matchStart, matchEnd);
}

/// Paginated search results.
class MessageSearchResults {
  final String query;
  final List<MessageSearchResult> results;
  final int totalCount;
  final int offset;
  final bool hasMore;

  const MessageSearchResults({
    required this.query,
    required this.results,
    required this.totalCount,
    required this.offset,
    required this.hasMore,
  });

  /// Empty results for initial state.
  static const empty = MessageSearchResults(
    query: '',
    results: [],
    totalCount: 0,
    offset: 0,
    hasMore: false,
  );
}
