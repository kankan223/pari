import 'base_repository.dart';
import 'conversation.dart';

/// Repository for Vault conversations (Task 3.2).
///
/// Extends the standard CRUD contract with Vault-specific queries. All data
/// is read/written through the encrypted local store; outbound sync flows
/// through the injected [SyncSink] port only.
abstract class ConversationRepository implements BaseRepository<Conversation> {
  /// Finds the conversation with the peer identified by [participantHash]
  /// (blind hash), or null when no such conversation exists locally.
  Future<Conversation?> getByParticipantHash(String participantHash);
}
