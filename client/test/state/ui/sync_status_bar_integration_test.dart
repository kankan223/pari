import 'dart:async';
import 'dart:typed_data';

import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/repository/domain/sync_sink.dart';
import 'package:civic_commons/state/data/local_data_stream_controller.dart';
import 'package:civic_commons/state/data/local_sync_status_bloc.dart';
import 'package:civic_commons/state/ui/sync_status_bar.dart';
import 'package:civic_commons/sync/data/background_sync_worker.dart';
import 'package:civic_commons/sync/domain/network_state.dart';
import 'package:civic_commons/sync/domain/reconnection_sync_trigger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../sync/fakes.dart';
import '../../state/fakes.dart';

/// VERIFY (Task 5.4): triggering a real sync (reconnection trigger → real
/// background worker → queue drained) updates the status bar UI end-to-end —
/// the same production wiring, driven through a real [LocalSyncStatusBloc].
void main() {
  testWidgets(
      'sync fired on reconnection drains the queue and the bar goes '
      'QUEUED -> LIVE', (tester) async {
    final network = FakeNetworkInfoProvider();
    final queue = FakeSyncQueueRepository()
      ..seed([_pendingItem('q1'), _pendingItem('q2')]);
    final queueChanges = LocalDataStreamController<SyncQueueItem>();
    final sink = _AcknowledgingSink();

    final worker = BackgroundSyncWorker(queue: queue, sink: sink);
    final trigger = ReconnectionSyncTrigger(network: network, worker: worker);
    final sub = trigger.start();

    final bloc = LocalSyncStatusBloc(
      network: network,
      queueRepository: queue,
      queueChanges: queueChanges,
    );
    // Pump FIRST so the StreamBuilder subscribes before the bloc emits — the
    // broadcast state stream does not replay past emissions.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SyncStatusBar(bloc: bloc)),
    ));
    await bloc.start();
    await tester.pump();
    await tester.pump();

    // Online with a seeded queue: QUEUED with a badge of 2.
    expect(find.text('QUEUED'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // Flap the network so the reconnection trigger fires a real sync run.
    network.emit(NetworkStatus.offline);
    await tester.pump();
    await tester.pump();
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('QUEUED'), findsNothing);

    network.emit(NetworkStatus.online);
    // The trigger fires runOnce() (async); let the worker drain the queue.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();

    // The worker drains the queue; push the post-drain snapshot the way the
    // repository layer would, then the bloc recomputes to LIVE.
    queueChanges.emit(await queue.getAll());
    await tester.pump();
    await tester.pump();

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('QUEUED'), findsNothing);
    expect(find.text('2'), findsNothing);

    // NOTE: awaiting broadcast StreamController.close() futures hangs inside
    // the testWidgets fake-async zone (verified empirically), so the async
    // teardown runs in the REAL async zone via runAsync.
    await tester.runAsync(() async {
      await bloc.close();
      await queueChanges.close();
      await sub.cancel();
    });
    network.dispose();
  });

  testWidgets('an in-flight sync run shows the subtle progress indicator',
      (tester) async {
    final network = FakeNetworkInfoProvider();
    final queue = FakeSyncQueueRepository()..seed([_pendingItem('q1')]);
    final queueChanges = LocalDataStreamController<SyncQueueItem>();
    final gate = _GatedSink();

    // A worker whose push blocks until the test releases the gate: the item
    // stays in_progress, so isSyncing stays true and the bar shows progress.
    final worker = BackgroundSyncWorker(queue: queue, sink: gate);
    final trigger = ReconnectionSyncTrigger(network: network, worker: worker);
    final sub = trigger.start();

    final bloc = LocalSyncStatusBloc(
      network: network,
      queueRepository: queue,
      queueChanges: queueChanges,
    );
    // Pump FIRST so the StreamBuilder subscribes before the bloc emits.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SyncStatusBar(bloc: bloc)),
    ));
    await bloc.start();
    await tester.pump();
    await tester.pump();
    expect(find.text('QUEUED'), findsOneWidget);

    // Reconnect: the trigger fires the worker; the item is in_progress now.
    network.emit(NetworkStatus.online);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    queueChanges.emit([
      _pendingItem('q1').copyWith(status: SyncQueueStatus.inProgress),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Release the gate: the push completes, item succeeds, queue drains.
    gate.release();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    queueChanges.emit(await queue.getAll());
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('LIVE'), findsOneWidget);

    // See the teardown note in the first test: close futures hang in the
    // fake-async zone, so they run in the real async zone.
    await tester.runAsync(() async {
      await bloc.close();
      await queueChanges.close();
      await sub.cancel();
    });
    network.dispose();
  });
}

SyncQueueItem _pendingItem(String id) => SyncQueueItem(
      id: id,
      operationType: SyncOperationType.create,
      payload: Uint8List.fromList([1, 2, 3]),
      createdAt: DateTime.utc(2026, 8, 2),
    );

/// Acknowledges every push (like a healthy remote).
class _AcknowledgingSink implements SyncSink {
  @override
  Future<SyncPushOutcome> push(SyncQueueItem item) async =>
      const SyncPushOutcome.acknowledged();
}

/// Holds pushes open until [release] — simulates an in-flight network call.
class _GatedSink implements SyncSink {
  final List<SyncQueueItem> pushed = [];
  Completer<void>? _gate;

  @override
  Future<SyncPushOutcome> push(SyncQueueItem item) async {
    pushed.add(item);
    _gate ??= Completer<void>();
    await _gate!.future;
    return const SyncPushOutcome.acknowledged();
  }

  void release() => _gate?.complete();
}
