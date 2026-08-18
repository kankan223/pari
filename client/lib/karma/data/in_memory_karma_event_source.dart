import 'dart:async';

import '../domain/karma_event.dart';
import '../domain/karma_event_source.dart';

/// In-memory [KarmaEventSource] (Task 10.2).
///
/// Dev/harness stand-in for the deferred server-side NATS consumer
/// (MASTER_PLAN §10.2). Emits locally-supplied inbound events onto a
/// broadcast stream. Production wiring swaps in the NATS-backed consumer
/// with the Phase-4 infra surface.
class InMemoryKarmaEventSource implements KarmaEventSource {
  final StreamController<KarmaEvent> _controller =
      StreamController<KarmaEvent>.broadcast();

  @override
  Stream<KarmaEvent> get events => _controller.stream;

  /// Pushes [event] to subscribers.
  void emit(KarmaEvent event) => _controller.add(event);

  Future<void> close() => _controller.close();
}
