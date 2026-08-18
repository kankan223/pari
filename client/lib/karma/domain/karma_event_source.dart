import 'karma_event.dart';

/// Port for INBOUND karma events (Task 10.2).
///
/// MASTER_PLAN §10.2 "Implement karma event consumption from NATS" is a
/// SERVER-side concern (the Phase-4 NATS JetStream surface). On the client
/// this port models the seam: events that arrive from the sync transport
/// (e.g. a server-confirmed Peer Review result) land here and are recorded
/// into the local ledger. The production NATS consumer is deferred with the
/// Phase-4 infra surface; the harness wires the in-memory implementation.
///
/// SECURITY CHECKPOINT (10.2): inbound events carry only blinded actors +
/// fixed actions — the same zero-identity envelope as [KarmaEvent].
abstract class KarmaEventSource {
  /// A stream of inbound karma events.
  Stream<KarmaEvent> get events;
}
