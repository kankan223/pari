import 'dart:async';

import '../../repository/domain/conversation.dart';
import '../../repository/domain/conversation_repository.dart';
import '../domain/conversation_bloc.dart';
import '../domain/conversation_state.dart';
import '../domain/local_data_stream.dart';

/// Local-database-backed [ConversationBloc] (data layer).
///
/// Subscribes to the [LocalDataStream] of conversations and maps each
/// snapshot to a UI-safe [ConversationState] of summaries. The BLoC never
/// touches the network — the repository + stream are the only collaborators.
class LocalConversationBloc implements ConversationBloc {
  final ConversationRepository _repository;
  final LocalDataStream<Conversation> _database;
  final StreamController<ConversationState> _controller =
      StreamController<ConversationState>.broadcast();
  StreamSubscription<List<Conversation>>? _sub;

  LocalConversationBloc({
    required ConversationRepository repository,
    required LocalDataStream<Conversation> database,
  })  : _repository = repository,
        _database = database;

  @override
  Stream<ConversationState> get state => _controller.stream;

  @override
  Future<void> start() async {
    if (_sub != null) {
      return;
    }
    _sub = _database.changes.listen((snapshots) {
      _emit(snapshots);
    });
    // Initial snapshot from the local store so the UI renders immediately.
    await refresh();
  }

  @override
  Future<void> refresh() async {
    _emit(await _repository.getAll());
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _controller.close();
  }

  void _emit(List<Conversation> conversations) {
    _controller.add(
      ConversationState(
        conversations:
            conversations.map(ConversationSummary.from).toList(growable: false),
        hasLoaded: true,
      ),
    );
  }
}
