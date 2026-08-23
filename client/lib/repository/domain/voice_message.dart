import 'dart:typed_data';

/// A voice message in a conversation.
///
/// SECURITY: voice bytes are encrypted at rest with AES-256-GCM before
/// they leave the device. The server sees opaque ciphertext only.
/// No identity, phone number, or PII is attached to voice messages.
class VoiceMessage {
  final String id;
  final String conversationId;
  final String messageId;

  /// Duration of the recording in milliseconds.
  final int durationMs;

  /// Encrypted audio bytes (AES-256-GCM sealed).
  final Uint8List encryptedBytes;

  /// Audio format (e.g., "audio/aac", "audio/ogg").
  final String format;

  /// When the voice message was recorded.
  final DateTime createdAt;

  const VoiceMessage({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.durationMs,
    required this.encryptedBytes,
    this.format = 'audio/aac',
    required this.createdAt,
  });

  VoiceMessage copyWith({
    int? durationMs,
    Uint8List? encryptedBytes,
    String? format,
  }) =>
      VoiceMessage(
        id: id,
        conversationId: conversationId,
        messageId: messageId,
        durationMs: durationMs ?? this.durationMs,
        encryptedBytes: encryptedBytes ?? this.encryptedBytes,
        format: format ?? this.format,
        createdAt: createdAt,
      );
}
