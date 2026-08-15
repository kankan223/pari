import 'base_repository.dart';
import 'message.dart';

/// Repository for Vault messages with local-first read/write (Task 3.2).
///
/// Reads always come from the encrypted local store; writes persist locally
/// first and are queued for background sync. Never performs direct HTTP.
abstract class MessageRepository implements BaseRepository<Message> {
  /// Every message in the conversation identified by [conversationId],
  /// oldest first.
  Future<List<Message>> getByConversation(String conversationId);

  /// Every message not yet acknowledged by the remote (local-first flag).
  Future<List<Message>> getUndelivered();
}
