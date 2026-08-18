import 'package:civic_commons/karma/data/in_memory_karma_event_source.dart';
import 'package:civic_commons/karma/domain/karma_action.dart';
import 'package:civic_commons/karma/domain/karma_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('InMemoryKarmaEventSource broadcasts emitted events', () async {
    final source = InMemoryKarmaEventSource();
    final received = <KarmaEvent>[];
    final sub = source.events.listen(received.add);

    final event = KarmaEvent(
      seq: 0,
      eventId: '11111111-1111-4111-8111-111111111111',
      actorHash: 'a' * 64,
      action: KarmaAction.ledgerPostVerified,
      delta: 5,
      balanceAfter: 5,
      at: DateTime.utc(2026, 8, 18),
      prevHash: '0' * 64,
      selfHash: '0' * 64,
    );
    source.emit(event);

    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    expect(received.single.eventId, event.eventId);
    expect(received.single.actorHash, 'a' * 64);
    expect(received.single.action, KarmaAction.ledgerPostVerified);

    await sub.cancel();
    await source.close();
  });

  test('a late subscriber misses earlier events (broadcast semantics)',
      () async {
    final source = InMemoryKarmaEventSource();
    final first = KarmaEvent(
      seq: 0,
      eventId: '11111111-1111-4111-8111-111111111111',
      actorHash: 'a' * 64,
      action: KarmaAction.academyModuleCompleted,
      delta: 2,
      balanceAfter: 2,
      at: DateTime.utc(2026, 8, 18),
      prevHash: '0' * 64,
      selfHash: '0' * 64,
    );
    source.emit(first);

    final received = <KarmaEvent>[];
    final sub = source.events.listen(received.add);
    await Future<void>.delayed(Duration.zero);
    expect(received, isEmpty);

    await sub.cancel();
    await source.close();
  });
}
