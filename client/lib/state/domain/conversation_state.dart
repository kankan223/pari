import '../../repository/domain/conversation.dart';

/// UI-safe projection of a [Conversation].
///
/// SECURITY (Task 3.5): the BLoC state deliberately EXCLUDES the
/// [Conversation.encryptedSessionState] bytes — the UI never receives
/// session ciphertext, and no raw/decrypted data can be logged from state.
class ConversationSummary {
  final String id;
  final String participantHash;

  const ConversationSummary({required this.id, required this.participantHash});

  factory ConversationSummary.from(Conversation c) =>
      ConversationSummary(id: c.id, participantHash: c.participantHash);
}

/// Immutable BLoC state for the conversation list (Vault).
class ConversationState {
  final List<ConversationSummary> conversations;
  final bool hasLoaded;

  const ConversationState(
      {this.conversations = const [], this.hasLoaded = false});

  ConversationState copyWith({
    List<ConversationSummary>? conversations,
    bool? hasLoaded,
  }) =>
      ConversationState(
        conversations: conversations ?? this.conversations,
        hasLoaded: hasLoaded ?? this.hasLoaded,
      );
}
