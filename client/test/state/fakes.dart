import 'dart:typed_data';

import 'package:civic_commons/repository/domain/conversation.dart';
import 'package:civic_commons/repository/domain/conversation_repository.dart';
import 'package:civic_commons/repository/domain/message.dart';
import 'package:civic_commons/repository/domain/message_repository.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/repository/domain/sync_queue_repository.dart';

/// In-memory [ConversationRepository] fake (Task 3.5 tests).
class FakeConversationRepository implements ConversationRepository {
  final Map<String, Conversation> _store = {};

  void seed(List<Conversation> conversations) {
    for (final c in conversations) {
      _store[c.id] = c;
    }
  }

  @override
  Future<Conversation> create(Conversation entity) async {
    _store[entity.id] = entity;
    return entity;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<List<Conversation>> getAll() async => _store.values.toList();

  @override
  Future<Conversation?> getById(String id) async => _store[id];

  @override
  Future<Conversation?> getByParticipantHash(String participantHash) async {
    for (final c in _store.values) {
      if (c.participantHash == participantHash) {
        return c;
      }
    }
    return null;
  }

  @override
  Future<Conversation> update(Conversation entity) async {
    _store[entity.id] = entity;
    return entity;
  }
}

/// In-memory [MessageRepository] fake (Task 3.5 tests).
class FakeMessageRepository implements MessageRepository {
  final Map<String, Message> _store = {};

  void seed(List<Message> messages) {
    for (final m in messages) {
      _store[m.id] = m;
    }
  }

  @override
  Future<Message> create(Message entity) async {
    _store[entity.id] = entity;
    return entity;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<List<Message>> getAll() async => _store.values.toList();

  @override
  Future<Message?> getById(String id) async => _store[id];

  @override
  Future<List<Message>> getByConversation(String conversationId) async =>
      _store.values
          .where((m) => m.conversationId == conversationId)
          .toList();

  @override
  Future<List<Message>> getUndelivered() async =>
      _store.values.where((m) => !m.delivered).toList();

  @override
  Future<Message> update(Message entity) async {
    _store[entity.id] = entity;
    return entity;
  }
}

/// In-memory [SyncQueueRepository] fake (Task 3.5 tests).
class FakeSyncQueueRepository implements SyncQueueRepository {
  final Map<String, SyncQueueItem> _store = {};
  int _sequence = 0;

  void seed(List<SyncQueueItem> items) {
    for (final i in items) {
      _store[i.id] = i;
    }
  }

  @override
  Future<SyncQueueItem> create(SyncQueueItem entity) async {
    _store[entity.id] = entity;
    return entity;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<List<SyncQueueItem>> getAll() async => _store.values.toList();

  @override
  Future<SyncQueueItem?> getById(String id) async => _store[id];

  @override
  Future<SyncQueueItem> enqueue({
    required SyncOperationType operationType,
    required Uint8List payload,
  }) {
    final item = SyncQueueItem(
      id: 'q${_sequence++}',
      operationType: operationType,
      payload: payload,
      createdAt: DateTime.utc(2026, 8, 2),
    );
    _store[item.id] = item;
    return Future.value(item);
  }

  @override
  Future<List<SyncQueueItem>> getPending() async => _store.values
      .where((i) => i.status == SyncQueueStatus.pending)
      .toList();

  @override
  Future<void> markInProgress(String id) async {
    final item = _store[id];
    if (item != null) {
      _store[id] = item.copyWith(status: SyncQueueStatus.inProgress);
    }
  }

  @override
  Future<void> markSuccess(String id) async {
    final item = _store[id];
    if (item != null) {
      _store[id] = item.copyWith(status: SyncQueueStatus.success);
    }
  }

  @override
  Future<void> markFailed(String id) async {
    final item = _store[id];
    if (item != null) {
      _store[id] = item.copyWith(
        status: SyncQueueStatus.failed,
        retryCount: item.retryCount + 1,
      );
    }
  }

  @override
  Future<SyncQueueItem> update(SyncQueueItem entity) async {
    _store[entity.id] = entity;
    return entity;
  }
}
