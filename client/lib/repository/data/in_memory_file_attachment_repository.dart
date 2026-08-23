import '../domain/file_attachment.dart';
import '../domain/file_attachment_repository.dart';

/// In-memory implementation of [FileAttachmentRepository] for dev/test.
class InMemoryFileAttachmentRepository implements FileAttachmentRepository {
  final Map<String, FileAttachment> _store = {};

  @override
  Future<FileAttachment> create(FileAttachment attachment) async {
    _store[attachment.id] = attachment;
    return attachment;
  }

  @override
  Future<FileAttachment?> getById(String id) async => _store[id];

  @override
  Future<List<FileAttachment>> getByMessageId(String messageId) async =>
      _store.values.where((a) => a.messageId == messageId).toList();

  @override
  Future<List<FileAttachment>> getByConversationId(String conversationId) async =>
      _store.values
          .where((a) => a.conversationId == conversationId)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> delete(String id) async => _store.remove(id);
}
