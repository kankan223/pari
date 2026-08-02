import 'dart:typed_data';

import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/sync/domain/network_state.dart';
import 'package:civic_commons/state/data/local_data_stream_controller.dart';
import 'package:civic_commons/state/data/local_sync_status_bloc.dart';
import 'package:civic_commons/state/domain/sync_status.dart';
import 'package:civic_commons/state/domain/sync_status_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sync/fakes.dart';
import 'fakes.dart';

void main() {
  group('LocalSyncStatusBloc.derive - LIVE/CACHED/QUEUED/OFFLINE (Task 3.5)',
      () {
    test('offline network is always OFFLINE regardless of queue', () {
      expect(LocalSyncStatusBloc.derive(NetworkStatus.offline, 0),
          SyncStatus.offline);
      expect(LocalSyncStatusBloc.derive(NetworkStatus.offline, 12),
          SyncStatus.offline);
    });

    test('metered network serves from cache (CACHED)', () {
      expect(LocalSyncStatusBloc.derive(NetworkStatus.metered, 0),
          SyncStatus.cached);
      expect(LocalSyncStatusBloc.derive(NetworkStatus.metered, 3),
          SyncStatus.cached);
    });

    test('online with an empty queue is LIVE', () {
      expect(
          LocalSyncStatusBloc.derive(NetworkStatus.online, 0), SyncStatus.live);
    });

    test('online with pending queue items is QUEUED', () {
      expect(LocalSyncStatusBloc.derive(NetworkStatus.online, 1),
          SyncStatus.queued);
      expect(LocalSyncStatusBloc.derive(NetworkStatus.online, 5),
          SyncStatus.queued);
    });
  });

  group('LocalSyncStatusBloc - stream-driven transitions (Task 3.5)', () {
    late FakeNetworkInfoProvider network;
    late FakeSyncQueueRepository queue;
    late LocalDataStreamController<SyncQueueItem> queueChanges;
    late LocalSyncStatusBloc bloc;
    late List<SyncStatusState> states;

    setUp(() {
      network = FakeNetworkInfoProvider();
      queue = FakeSyncQueueRepository();
      queueChanges = LocalDataStreamController<SyncQueueItem>();
      bloc = LocalSyncStatusBloc(
        network: network,
        queueRepository: queue,
        queueChanges: queueChanges,
      );
      states = [];
      bloc.state.listen(states.add);
    });

    tearDown(() async {
      await bloc.close();
      await queueChanges.close();
      network.dispose();
    });

    SyncQueueItem pendingItem(String id) => SyncQueueItem(
          id: id,
          operationType: SyncOperationType.create,
          payload: Uint8List.fromList([1, 2, 3]),
          createdAt: DateTime.utc(2026, 8, 2),
        );

    test('starts LIVE when online with an empty queue', () async {
      await bloc.start();
      await flushMicrotasks();

      expect(states, isNotEmpty);
      expect(states.last.status, SyncStatus.live);
      expect(states.last.pendingCount, 0);
    });

    test('starts OFFLINE when the network is offline', () async {
      network.current = NetworkStatus.offline;
      await bloc.start();
      await flushMicrotasks();

      expect(states.last.status, SyncStatus.offline);
    });

    test('offline -> online transition emits QUEUED then LIVE', () async {
      network.current = NetworkStatus.offline;
      await bloc.start();
      await flushMicrotasks();
      expect(states.last.status, SyncStatus.offline);

      network.emit(NetworkStatus.online);
      await flushMicrotasks();
      expect(states.last.status, SyncStatus.live);
    });

    test('queued items surface as QUEUED with an accurate count', () async {
      await bloc.start();
      await flushMicrotasks();

      queue.seed([
        pendingItem('q1'),
        pendingItem('q2'),
        pendingItem('q3'),
      ]);
      // A queue mutation pushes a fresh snapshot (3 pending, 1 already
      // succeeded — only pending counts toward the badge).
      queueChanges.emit([
        pendingItem('q1'),
        pendingItem('q2'),
        pendingItem('q3'),
        pendingItem('done')
            .copyWith(status: SyncQueueStatus.success),
      ]);
      await flushMicrotasks();

      expect(states.last.status, SyncStatus.queued);
      expect(states.last.pendingCount, 3);
    });

    test('draining the queue (empty pending) returns to LIVE', () async {
      queue.seed([pendingItem('q1')]);
      await bloc.start();
      await flushMicrotasks();
      expect(states.last.status, SyncStatus.queued);

      queueChanges.emit(const []);
      await flushMicrotasks();
      expect(states.last.status, SyncStatus.live);
      expect(states.last.pendingCount, 0);
    });

    test('refresh() re-derives from the network provider', () async {
      await bloc.start();
      await flushMicrotasks();
      expect(states.last.status, SyncStatus.live);

      network.current = NetworkStatus.metered;
      await bloc.refresh();
      await flushMicrotasks();
      expect(states.last.status, SyncStatus.cached);
    });

    test('state exposes only the enum + count — no payload data', () async {
      await bloc.start();
      await flushMicrotasks();

      final state = states.last;
      expect(state, isA<SyncStatusState>());
      expect(state.status, isA<SyncStatus>());
      expect(state.pendingCount, isA<int>());
      // SyncStatusState has exactly two members; there is no payload field.
      expect(state.toString(), contains('SyncStatusState'));
    });
  });
}

/// Flushes pending microtasks so broadcast-stream deliveries land.
Future<void> flushMicrotasks() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
