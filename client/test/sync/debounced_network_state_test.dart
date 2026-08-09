import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/sync/domain/debounced_network_info_provider.dart';
import 'package:civic_commons/sync/domain/network_state.dart';

import 'fakes.dart';

/// VERIFY (Task 5.1): network state listener with 500ms debouncing — rapid
/// flapping collapses to one emission; the last status observed wins; the
/// quiet window is configurable.
void main() {
  group('DebouncedNetworkInfoProvider - debounced statusChanges (Task 5.1)',
      () {
    test('emits a status after the quiet window elapses', () {
      fakeAsync((async) {
        final inner = FakeNetworkInfoProvider();
        final provider = DebouncedNetworkInfoProvider(inner,
            debounce: const Duration(milliseconds: 500));
        final seen = <NetworkStatus>[];
        late StreamSubscription<NetworkStatus> sub;
        sub = provider.statusChanges.listen((s) {
          seen.add(s);
          if (seen.length == 1) {
            sub.cancel();
          }
        });

        inner.emit(NetworkStatus.online);
        expect(seen, isEmpty, reason: 'nothing before the window elapses');

        async.elapse(const Duration(milliseconds: 499));
        expect(seen, isEmpty, reason: 'still inside the window');

        async.elapse(const Duration(milliseconds: 1));
        expect(seen, [NetworkStatus.online], reason: 'fires after 500ms');

        inner.dispose();
      });
    });

    test('rapid flapping collapses into a single trailing emission', () {
      fakeAsync((async) {
        final inner = FakeNetworkInfoProvider();
        final provider = DebouncedNetworkInfoProvider(inner,
            debounce: const Duration(milliseconds: 500));
        final seen = <NetworkStatus>[];
        late StreamSubscription<NetworkStatus> sub;
        sub = provider.statusChanges.listen((s) {
          seen.add(s);
          if (seen.length == 1) {
            sub.cancel();
          }
        });

        // Wifi → cellular → wifi → none inside the window: only the LAST
        // status (offline) is emitted after quiet.
        inner.emit(NetworkStatus.online);
        async.elapse(const Duration(milliseconds: 100));
        inner.emit(NetworkStatus.metered);
        async.elapse(const Duration(milliseconds: 100));
        inner.emit(NetworkStatus.online);
        async.elapse(const Duration(milliseconds: 100));
        inner.emit(NetworkStatus.offline);

        async.elapse(const Duration(milliseconds: 500));
        expect(seen, [NetworkStatus.offline]);

        inner.dispose();
      });
    });

    test('a new change restarts the window (no early emission)', () {
      fakeAsync((async) {
        final inner = FakeNetworkInfoProvider();
        final provider = DebouncedNetworkInfoProvider(inner,
            debounce: const Duration(milliseconds: 500));
        final seen = <NetworkStatus>[];
        late StreamSubscription<NetworkStatus> sub;
        sub = provider.statusChanges.listen((s) {
          seen.add(s);
          if (seen.length == 1) {
            sub.cancel();
          }
        });

        inner.emit(NetworkStatus.online);
        async.elapse(const Duration(milliseconds: 400));
        inner.emit(NetworkStatus.offline); // restarts the 500ms window
        async.elapse(const Duration(milliseconds: 400));
        expect(seen, isEmpty, reason: 'window was restarted at t=400');

        async.elapse(const Duration(milliseconds: 100));
        expect(seen, [NetworkStatus.offline]);

        inner.dispose();
      });
    });

    test('currentStatus passes through unchanged (one-shot authoritative)',
        () async {
      final inner = FakeNetworkInfoProvider()..current = NetworkStatus.metered;
      final provider = DebouncedNetworkInfoProvider(inner,
          debounce: const Duration(milliseconds: 500));

      expect(await provider.currentStatus(), NetworkStatus.metered);

      inner.dispose();
    });

    test('a custom debounce window is honored', () {
      fakeAsync((async) {
        final inner = FakeNetworkInfoProvider();
        final provider = DebouncedNetworkInfoProvider(inner,
            debounce: const Duration(milliseconds: 50));
        final seen = <NetworkStatus>[];
        late StreamSubscription<NetworkStatus> sub;
        sub = provider.statusChanges.listen((s) {
          seen.add(s);
          if (seen.length == 1) {
            sub.cancel();
          }
        });

        inner.emit(NetworkStatus.online);
        async.elapse(const Duration(milliseconds: 49));
        expect(seen, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(seen, [NetworkStatus.online]);

        inner.dispose();
      });
    });
  });
}
