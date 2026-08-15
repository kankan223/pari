import '../../repository/domain/message.dart';
import 'message_state.dart';

/// Which side of a thread a [MessageSummary] occupies.
///
/// The Vault renders sent bubbles (right-aligned, Vault Blue) and received
/// bubbles (left-aligned, surface white) per DESIGN §6.3.
enum MessageSide { sent, received }

/// Maps a [MessageSummary] to its side.
///
/// Task 6.3: the [Message] entity now carries an explicit [MessageDirection]
/// field, so the default resolver reads THAT field — the old heuristic
/// (`delivered ? received : sent`) is superseded and removed. Screens may
/// still inject an explicit resolver, but the default is authoritative on
/// the persisted direction.
typedef MessageSideResolver = MessageSide Function(MessageSummary summary);

/// Default [MessageSideResolver]: explicit direction sent → sent,
/// otherwise received.
///
/// SECURITY CHECKPOINT (Task 6.1/6.3): the resolver operates on the
/// direction field only — no content, no identifiers, no payloads.
MessageSide defaultMessageSide(MessageSummary summary) =>
    summary.direction == MessageDirection.sent
        ? MessageSide.sent
        : MessageSide.received;
