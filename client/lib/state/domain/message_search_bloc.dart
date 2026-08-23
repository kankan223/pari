import 'dart:async';

import '../../repository/domain/message_search_repository.dart';
import '../../repository/domain/message_search_result.dart';

/// BLoC for searching through message history.
///
/// Manages the search query, results, loading state, and pagination.
/// Supports both global search (across all conversations) and
/// conversation-scoped search.
class MessageSearchBloc {
  final MessageSearchRepository _repo;

  final _controller = StreamController<MessageSearchState>.broadcast();
  MessageSearchState _state = const MessageSearchState();
  Timer? _debounce;

  MessageSearchBloc({required MessageSearchRepository repo}) : _repo = repo;

  Stream<MessageSearchState> get state => _controller.stream;
  MessageSearchState get currentState => _state;

  /// Update the search query with debouncing (300ms).
  void query(String text, {String? conversationId}) {
    _debounce?.cancel();
    _state = _state.copyWith(
      query: text,
      isLoading: true,
      conversationId: conversationId,
    );
    _emit();

    if (text.trim().isEmpty) {
      _state = _state.copyWith(
        results: MessageSearchResults.empty,
        isLoading: false,
      );
      _emit();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(text, conversationId: conversationId);
    });
  }

  /// Immediately search without debouncing.
  void searchNow(String text, {String? conversationId}) {
    _debounce?.cancel();
    _state = _state.copyWith(
      query: text,
      isLoading: true,
      conversationId: conversationId,
    );
    _emit();
    _performSearch(text, conversationId: conversationId);
  }

  /// Load the next page of results.
  void loadMore() {
    if (_state.isLoading || !_state.hasMore) return;
    _state = _state.copyWith(isLoading: true);
    _emit();
    _performSearch(
      _state.query,
      conversationId: _state.conversationId,
      offset: _state.results.results.length,
    );
  }

  /// Clear the current search.
  void clear() {
    _debounce?.cancel();
    _state = const MessageSearchState();
    _emit();
  }

  Future<void> _performSearch(
    String text, {
    String? conversationId,
    int offset = 0,
  }) async {
    try {
      final results = await _repo.search(
        query: text,
        conversationId: conversationId,
        limit: 20,
        offset: offset,
      );

      if (offset == 0) {
        _state = _state.copyWith(
          results: results,
          isLoading: false,
        );
      } else {
        // Append to existing results.
        _state = _state.copyWith(
          results: MessageSearchResults(
            query: results.query,
            results: [..._state.results.results, ...results.results],
            totalCount: results.totalCount,
            offset: results.offset,
            hasMore: results.hasMore,
          ),
          isLoading: false,
        );
      }
      _emit();
    } catch (_) {
      _state = _state.copyWith(isLoading: false);
      _emit();
    }
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_state);
    }
  }

  Future<void> close() async {
    _debounce?.cancel();
    await _controller.close();
  }
}

/// State for message search.
class MessageSearchState {
  final String query;
  final MessageSearchResults results;
  final bool isLoading;
  final String? conversationId;

  const MessageSearchState({
    this.query = '',
    this.results = MessageSearchResults.empty,
    this.isLoading = false,
    this.conversationId,
  });

  bool get hasResults => results.results.isNotEmpty;
  bool get hasMore => results.hasMore;
  int get totalCount => results.totalCount;

  MessageSearchState copyWith({
    String? query,
    MessageSearchResults? results,
    bool? isLoading,
    String? conversationId,
    bool clearConversationId = false,
  }) =>
      MessageSearchState(
        query: query ?? this.query,
        results: results ?? this.results,
        isLoading: isLoading ?? this.isLoading,
        conversationId:
            clearConversationId ? null : (conversationId ?? this.conversationId),
      );
}
