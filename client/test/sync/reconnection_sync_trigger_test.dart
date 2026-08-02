import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/sync/domain/network_state.dart';
import 'package:civic_commons/sync/domain/reconnection_sync_trigger.dart';

import 'fakes.dart';

/// VERIFY (Task 3.4): the sync trigger fires on network reconnection.
void main() {
  late FakeNetworkInfoProvider network;
  late RecordingSyncWorker worker;
  late ReconnectionSyncTrigger trigger;

  setUp(() {
    network = FakeNetworkInfoProvider();
    worker = RecordingSyncWorker();
    trigger = ReconnectionSyncTrigger(network: network, worker: worker);
  });

  tearDown(() => network.dispose());

  group('ReconnectionSyncTrigger - fires on offline→online', () {
    test('first online status change triggers a sync', () async {
      final sub = trigger.start();

      network.emit(NetworkStatus.online);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(worker.runCount, 1);
    });

    test('offline→online transition triggers exactly one sync', () async {
      final sub = trigger.start();
      network.emit(NetworkStatus.offline);

      network.emit(NetworkStatus.online);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(worker.runCount, 1);
    });

    test('metered→online transition also triggers a sync', () async {
      final sub = trigger.start();
      network.emit(NetworkStatus.metered);

      network.emit(NetworkStatus.online);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(worker.runCount, 1);
    });

    test('online→online does NOT re-trigger (no duplicate syncs)', () async {
      final sub = trigger.start();
      network.emit(NetworkStatus.online);

      network.emit(NetworkStatus.online);
      network.emit(NetworkStatus.online);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(worker.runCount, 1);
    });

    test('online→offline→online fires once per reconnection', () async {
      final sub = trigger.start();
      network.emit(NetworkStatus.online);
      network.emit(NetworkStatus.offline);

      network.emit(NetworkStatus.online);
      network.emit(NetworkStatus.offline);
      network.emit(NetworkStatus.online);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(worker.runCount, 3);
    });

    test('never fires while staying offline', () async {
      final sub = trigger.start();
      network.emit(NetworkStatus.offline);
      network.emit(NetworkStatus.offline);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(worker.runCount, 0);
    });

    test('online→offline does not fire', () async {
      final sub = trigger.start();
      network.emit(NetworkStatus.offline);
      network.emit(NetworkStatus.online);
      network.emit(NetworkStatus.offline);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(worker.runCount, 1);
    });
  });
}
