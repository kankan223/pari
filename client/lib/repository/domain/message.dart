import 'dart:typed_data';

/// Explicit direction of a Vault message (Task 6.3).
///
/// Replaces the implicit delivered-based heuristic (`delivered ? received :
/// sent`) used by the pre-6.3 [MessageSideResolver]: a message's side is now
/// an explicit, persisted property of the entity.
enum MessageDirection {
  sent,
  received;

  /// Stable wire/storage name (used by the SQLCipher row codec).
  String get wireName => switch (this) {
        MessageDirection.sent => 'sent',
        MessageDirection.received => 'received',
      };

  /// Parses a wire/storage name; unknown values fall back to [received]
  /// so rows written before the direction column landed never crash.
  static MessageDirection fromWireName(String? name) => switch (name) {
        'sent' => MessageDirection.sent,
        _ => MessageDirection.received,
      };
}

/// A Vault message (domain entity, Task 3.2).
///
/// Mirrors the `messages` table in `AppSchema`:
/// - [ciphertext] is the AES-256-GCM sealed message body — this entity NEVER
///   holds plaintext message content.
/// - [direction] is the explicit sent/received side (Task 6.3) — the UI's
///   bubble side comes from this field, never from a delivery heuristic.
/// - [delivered] is a local-first flag: locally created messages start with
///   `delivered = false` and flip to true once the sync layer confirms the
///   remote acknowledged them.
/// - [expiresAt] is the optional TTL-based expiry timestamp.
class Message {
  final String id;
  final String conversationId;

  /// Sealed message body (opaque ciphertext, never plaintext).
  final Uint8List ciphertext;

  /// Explicit sent/received direction (Task 6.3).
  final MessageDirection direction;

  /// Whether the remote has acknowledged delivery (local-first flag).
  final bool delivered;

  final DateTime? expiresAt;

  /// When the message was sent (local UTC timestamp).
  final DateTime sentAt;

  /// ID of the message this is a reply to (null if not a reply).
  final String? replyToId;

  /// Decrypted preview of the message being replied to (null if not a reply).
  final String? replyToContent;

  Message({
    required this.id,
    required this.conversationId,
    required this.ciphertext,
    required this.direction,
    this.delivered = false,
    this.expiresAt,
    DateTime? sentAt,
    this.replyToId,
    this.replyToContent,
  }) : sentAt = sentAt ?? DateTime.now().toUtc();

  Message copyWith({
    bool? delivered,
    DateTime? expiresAt,
    MessageDirection? direction,
    DateTime? sentAt,
    String? replyToId,
    String? replyToContent,
    bool clearReplyToId = false,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        ciphertext: ciphertext,
        direction: direction ?? this.direction,
        delivered: delivered ?? this.delivered,
        expiresAt: expiresAt ?? this.expiresAt,
        sentAt: sentAt ?? this.sentAt,
        replyToId: clearReplyToId ? null : (replyToId ?? this.replyToId),
        replyToContent: clearReplyToId ? null : (replyToContent ?? this.replyToContent),
      );
}
