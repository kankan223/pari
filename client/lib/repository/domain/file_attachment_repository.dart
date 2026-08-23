import 'file_attachment.dart';

/// Repository for file attachment persistence.
abstract class FileAttachmentRepository {
  Future<FileAttachment> create(FileAttachment attachment);
  Future<FileAttachment?> getById(String id);
  Future<List<FileAttachment>> getByMessageId(String messageId);
  Future<List<FileAttachment>> getByConversationId(String conversationId);
  Future<void> delete(String id);
}
