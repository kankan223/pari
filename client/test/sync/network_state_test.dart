import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/sync/domain/network_state.dart';
import 'package:civic_commons/sync/data/connectivity_network_info_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'fakes.dart';

/// VERIFY (Task 3.4): network state detection unit tests.
void main() {
  group('ConnectivityNetworkInfoProvider - status mapping', () {
    test('none maps to offline', () {
      expect(
        ConnectivityNetworkInfoProvider.map(ConnectivityResult.none),
        NetworkStatus.offline,
      );
    });

    test('mobile maps to metered', () {
      expect(
        ConnectivityNetworkInfoProvider.map(ConnectivityResult.mobile),
        NetworkStatus.metered,
      );
    });

    test('wifi/ethernet/vpn/bluetooth/other map to online', () {
      for (final result in [
        ConnectivityResult.wifi,
        ConnectivityResult.ethernet,
        ConnectivityResult.vpn,
        ConnectivityResult.bluetooth,
        ConnectivityResult.other,
      ]) {
        expect(
          ConnectivityNetworkInfoProvider.map(result),
          NetworkStatus.online,
          reason: '$result should map to online',
        );
      }
    });
  });

  group('NetworkInfoProvider - scripted stream (domain contract)', () {
    test('currentStatus returns the last known status', () async {
      final provider = FakeNetworkInfoProvider()..current = NetworkStatus.offline;
      expect(await provider.currentStatus(), NetworkStatus.offline);
      provider.dispose();
    });

    test('statusChanges emits each emitted change in order', () async {
      final provider = FakeNetworkInfoProvider();
      final seen = <NetworkStatus>[];

      final sub = provider.statusChanges.listen(seen.add);
      provider.emit(NetworkStatus.offline);
      provider.emit(NetworkStatus.online);
      provider.emit(NetworkStatus.metered);

      // Let microtasks flush before asserting.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      provider.dispose();

      expect(seen, [NetworkStatus.offline, NetworkStatus.online, NetworkStatus.metered]);
    });
  });
}
