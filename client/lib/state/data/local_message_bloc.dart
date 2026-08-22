import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../repository/domain/idempotency_key.dart';
import '../../repository/domain/message.dart';
import '../../repository/domain/message_repository.dart';
import '../domain/local_data_stream.dart';
import '../domain/message_bloc.dart';
import '../domain/message_cipher.dart';
import '../domain/message_state.dart';

/// Local-database-backed [MessageBloc] (data layer).
///
/// Streams UI-safe [MessageState] summaries for one conversation, sourced
/// from the [LocalDataStream] of messages. With a [MessageCipher] +
/// [participantHash] wired (Task 6.3), each message is decrypted before it
/// reaches the UI — the state carries [MessageSummary.content] (plaintext)
/// but NEVER [Message.ciphertext].
class LocalMessageBloc implements MessageBloc {
  final MessageRepository _repository;
  final LocalDataStream<Message> _database;
  final String _conversationId;
  final String? _participantHash;
  final MessageCipher? _cipher;
  final IdempotencyKeyGenerator _idGen;
  final StreamController<MessageState> _controller =
      StreamController<MessageState>.broadcast();
  StreamSubscription<List<Message>>? _sub;

  /// Monotonic snapshot sequence — the stale-pull guard (same pattern as
  /// [LocalConnectionRequestsBloc], Task 6.2): decrypt is async, so a
  /// refresh() pull and a database push can interleave; only the newest
  /// computation may emit.
  int _seq = 0;

  LocalMessageBloc({
    required MessageRepository repository,
    required LocalDataStream<Message> database,
    required String conversationId,
    String? participantHash,
    MessageCipher? cipher,
    IdempotencyKeyGenerator? idempotencyKeys,
  })  : _repository = repository,
        _database = database,
        _conversationId = conversationId,
        _participantHash = participantHash,
        _cipher = cipher,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator();

  /// Exposes the underlying repository for relay integration.
  MessageRepository get repository => _repository;
  /// Exposes the underlying data stream for relay integration.
  LocalDataStream<Message> get database => _database;

  @override
  Stream<MessageState> get state => _controller.stream;

  @override
  Future<void> start() async {
    if (_sub != null) {
      return;
    }
    _sub = _database.changes.listen((snapshots) {
      unawaited(_emit(_forConversation(snapshots)));
    });
    await refresh();
  }

  @override
  Future<void> refresh() async {
    await _emit(await _repository.getByConversation(_conversationId));
  }

  @override
  Future<void> send(String text) async {
    final participantHash = _participantHash;
    final cipher = _cipher;
    if (participantHash == null || cipher == null) {
      throw StateError(
          'Message encryption is not wired for conversation $_conversationId');
    }
    final plaintext = Uint8List.fromList(utf8.encode(text));
    final sealed = await cipher.encrypt(
      participantHash: participantHash,
      plaintext: plaintext,
    );
    final message = Message(
      id: _idGen.generate(),
      conversationId: _conversationId,
      ciphertext: sealed,
      direction: MessageDirection.sent,
    );
    await _repository.create(message);
    // The local-first write is persisted + queued; republish the thread.
    await refresh();
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _controller.close();
  }

  List<Message> _forConversation(List<Message> all) =>
      all.where((m) => m.conversationId == _conversationId).toList();

  Future<void> _emit(List<Message> messages) async {
    final seq = ++_seq;
    final cipher = _cipher;
    final participantHash = _participantHash;
    final summaries = <MessageSummary>[];
    for (final m in messages) {
      var summary = MessageSummary.from(m);
      if (cipher != null && participantHash != null) {
        try {
          final plaintext = await cipher.decrypt(
            participantHash: participantHash,
            ciphertext: m.ciphertext,
          );
          if (plaintext != null) {
            summary = summary.copyWith(
              content: utf8.decode(plaintext, allowMalformed: true),
            );
          }
        } catch (_) {
          // Undecryptable — keep content null so the UI shows the fixed
          // placeholder. Never propagate raw bytes or error detail.
        }
      }
      summaries.add(summary);
    }
    if (seq != _seq) {
      // A newer snapshot landed while this one decrypted — drop the stale
      // computation so an older pull can never overwrite a fresher push.
      return;
    }
    _controller.add(
      MessageState(
        conversationId: _conversationId,
        messages: summaries,
        hasLoaded: true,
      ),
    );
  }
}
