import '../../repository/domain/message.dart';

/// UI-safe projection of a [Message].
///
/// SECURITY (Task 3.5): the BLoC state deliberately EXCLUDES the
/// [Message.ciphertext] bytes — the UI receives only the decrypted
/// [content] (Task 6.3) or delivery metadata, and no ciphertext can be
/// logged from state.
///
/// Task 6.3: [direction] is the explicit sent/received side (persisted on
/// the [Message] entity) — the bubble side is derived from this field, never
/// from the old delivered-based heuristic. [content] is the DECRYPTED
/// plaintext, filled in by the BLoC via [MessageCipher]; it is null when a
/// session is unavailable or decryption fails, and the UI then shows the
/// fixed "[end-to-end encrypted]" placeholder.
class MessageSummary {
  final String id;
  final bool delivered;
  final DateTime? expiresAt;
  final MessageDirection direction;

  /// Decrypted message content, or null when undecryptable (placeholder
  /// fallback in the UI). Never the raw ciphertext.
  final String? content;

  /// When the message was sent (UTC timestamp for display in chat bubbles).
  final DateTime sentAt;

  MessageSummary({
    required this.id,
    this.delivered = false,
    this.expiresAt,
    this.direction = MessageDirection.received,
    this.content,
    DateTime? sentAt,
  }) : sentAt = sentAt ?? DateTime.now().toUtc();

  factory MessageSummary.from(Message m) => MessageSummary(
        id: m.id,
        delivered: m.delivered,
        expiresAt: m.expiresAt,
        direction: m.direction,
        sentAt: m.sentAt,
      );

  /// Sentinel so [copyWith] can explicitly clear [content] back to null
  /// (a previously-decrypted message that becomes undecryptable must be able
  /// to drop its stale plaintext — never keep it in state).
  static const Object _unset = _UnsetSentinel();

  MessageSummary copyWith({
    bool? delivered,
    DateTime? expiresAt,
    MessageDirection? direction,
    Object? content = _unset,
    DateTime? sentAt,
  }) =>
      MessageSummary(
        id: id,
        delivered: delivered ?? this.delivered,
        expiresAt: expiresAt ?? this.expiresAt,
        direction: direction ?? this.direction,
        content: identical(content, _unset) ? this.content : content as String?,
        sentAt: sentAt ?? this.sentAt,
      );
}



/// Const-constructible private sentinel type (see [MessageSummary.copyWith]).
class _UnsetSentinel {
  const _UnsetSentinel();
}

/// Immutable BLoC state for a single conversation's message thread.
class MessageState {
  final String conversationId;
  final List<MessageSummary> messages;
  final bool hasLoaded;

  /// Whether the peer is currently typing in this conversation.
  final bool isPeerTyping;

  /// The most recent message ID the peer has read (null = unknown).
  final String? lastReadMsgId;

  const MessageState({
    required this.conversationId,
    this.messages = const [],
    this.hasLoaded = false,
    this.isPeerTyping = false,
    this.lastReadMsgId,
  });

  MessageState copyWith({
    String? conversationId,
    List<MessageSummary>? messages,
    bool? hasLoaded,
    bool? isPeerTyping,
    String? lastReadMsgId,
    bool clearLastReadMsgId = false,
  }) =>
      MessageState(
        conversationId: conversationId ?? this.conversationId,
        messages: messages ?? this.messages,
        hasLoaded: hasLoaded ?? this.hasLoaded,
        isPeerTyping: isPeerTyping ?? this.isPeerTyping,
        lastReadMsgId: clearLastReadMsgId
            ? null
            : (lastReadMsgId ?? this.lastReadMsgId),
      );
}
