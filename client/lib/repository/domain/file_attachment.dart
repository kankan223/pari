import 'dart:typed_data';

/// A file or image attachment in a conversation.
///
/// SECURITY: [displayName] is a user-chosen label — NEVER a filesystem path,
/// NEVER persisted as-is (only the encrypted bytes are stored). The server
/// sees only opaque ciphertext in the Envelope; the metadata frame carries
/// the display name for UI purposes only.
class FileAttachment {
  final String id;
  final String conversationId;
  final String messageId;

  /// User-chosen display name (e.g., "photo.jpg"). NOT a filesystem path.
  final String displayName;

  /// MIME type (e.g., "image/jpeg", "application/pdf").
  final String mimeType;

  /// Original file size in bytes (before encryption).
  final int originalSize;

  /// Encrypted file bytes (AES-256-GCM sealed).
  final Uint8List encryptedBytes;

  /// Optional thumbnail bytes (small, low-res, for image previews).
  /// May be null for non-image files.
  final Uint8List? thumbnailBytes;

  /// When the file was attached.
  final DateTime createdAt;

  const FileAttachment({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.displayName,
    required this.mimeType,
    required this.originalSize,
    required this.encryptedBytes,
    this.thumbnailBytes,
    required this.createdAt,
  });

  /// Whether this attachment is an image (based on MIME type).
  bool get isImage => mimeType.startsWith('image/');

  FileAttachment copyWith({
    String? displayName,
    String? mimeType,
    int? originalSize,
    Uint8List? encryptedBytes,
    Uint8List? thumbnailBytes,
  }) =>
      FileAttachment(
        id: id,
        conversationId: conversationId,
        messageId: messageId,
        displayName: displayName ?? this.displayName,
        mimeType: mimeType ?? this.mimeType,
        originalSize: originalSize ?? this.originalSize,
        encryptedBytes: encryptedBytes ?? this.encryptedBytes,
        thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
        createdAt: createdAt,
      );
}
