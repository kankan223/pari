import 'package:civic_commons/relay/domain/relay_heartbeat.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A clock whose "now" tracks fake_async's elapsing time.
  (DateTime Function(), void Function(Duration)) makeClock(FakeAsync fake) {
    final now = <DateTime>[DateTime.fromMillisecondsSinceEpoch(0)];
    void advance(Duration d) {
      now[0] = now[0].add(d);
      fake.elapse(d);
    }

    return (() => now[0], advance);
  }

  group('RelayHeartbeat', () {
    test('fires onStale when no activity arrives within staleAfter', () {
      fakeAsync((fake) {
        var staleFired = 0;
        final (clock, advance) = makeClock(fake);
        final hb = RelayHeartbeat(
          staleAfter: const Duration(seconds: 30),
          clock: clock,
          onStale: () => staleFired++,
        );

        hb.start();
        expect(staleFired, 0);

        advance(const Duration(seconds: 29));
        expect(staleFired, 0, reason: 'still inside the silence window');

        advance(const Duration(seconds: 2)); // now 31s of silence
        expect(staleFired, 1, reason: 'stale window crossed → fired');

        hb.stop();
        fake.flushTimers();
      });
    });

    test('activity resets the staleness window', () {
      fakeAsync((fake) {
        var staleFired = 0;
        final (clock, advance) = makeClock(fake);
        final hb = RelayHeartbeat(
          staleAfter: const Duration(seconds: 30),
          clock: clock,
          onStale: () => staleFired++,
        );

        hb.start();
        // Keep the connection alive every 10s — never stale.
        for (var i = 0; i < 20; i++) {
          advance(const Duration(seconds: 10));
          hb.notifyActivity();
        }
        expect(staleFired, 0);

        hb.stop();
        fake.flushTimers();
      });
    });

    test('stop() is idempotent and cancels the watchdog', () {
      fakeAsync((fake) {
        var staleFired = 0;
        final (clock, advance) = makeClock(fake);
        final hb = RelayHeartbeat(
          staleAfter: const Duration(seconds: 30),
          clock: clock,
          onStale: () => staleFired++,
        );

        hb.start();
        hb.stop();
        hb.stop(); // idempotent
        advance(const Duration(minutes: 2));
        expect(staleFired, 0);
        fake.flushTimers();
      });
    });
  });
}
