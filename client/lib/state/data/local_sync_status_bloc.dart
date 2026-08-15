import 'dart:async';

import '../../repository/domain/sync_queue_item.dart';
import '../../repository/domain/sync_queue_repository.dart';
import '../../sync/domain/network_state.dart';
import '../domain/local_data_stream.dart';
import '../domain/sync_status.dart';
import '../domain/sync_status_bloc.dart';

/// Local-database-backed [SyncStatusBloc] (data layer, Task 3.5).
///
/// Derives [SyncStatusState] from the network status (via the injected
/// [NetworkInfoProvider]) and the local sync queue:
/// - offline network → [SyncStatus.offline]
/// - metered network → [SyncStatus.cached] (serve from the local cache,
///   defer sync to conserve data)
/// - online with pending queue items → [SyncStatus.queued]
/// - online with an empty queue → [SyncStatus.live]
///
/// The bloc only ever emits the enum plus a pending-item count — never
/// payloads, hashes, or decrypted content (SECURITY CHECKPOINT, Task 3.5).
class LocalSyncStatusBloc implements SyncStatusBloc {
  final NetworkInfoProvider _network;
  final SyncQueueRepository _queueRepository;
  final LocalDataStream<SyncQueueItem> _queueChanges;
  final DateTime Function() _clock;

  final StreamController<SyncStatusState> _controller =
      StreamController<SyncStatusState>.broadcast();

  StreamSubscription<NetworkStatus>? _networkSub;
  StreamSubscription<List<SyncQueueItem>>? _queueSub;

  NetworkStatus _lastNetwork = NetworkStatus.offline;
  int _lastPendingCount = 0;
  bool _isSyncing = false;
  bool _wasDraining = false;
  DateTime? _lastSyncAt;

  LocalSyncStatusBloc({
    required NetworkInfoProvider network,
    required SyncQueueRepository queueRepository,
    required LocalDataStream<SyncQueueItem> queueChanges,
    DateTime Function()? clock,
  })  : _network = network,
        _queueRepository = queueRepository,
        _queueChanges = queueChanges,
        _clock = clock ?? DateTime.now;

  /// Pure derivation exposed for unit testing (LIVE/CACHED/QUEUED/OFFLINE).
  static SyncStatus derive(NetworkStatus network, int pendingCount) {
    switch (network) {
      case NetworkStatus.offline:
        return SyncStatus.offline;
      case NetworkStatus.metered:
        return SyncStatus.cached;
      case NetworkStatus.online:
        return pendingCount > 0 ? SyncStatus.queued : SyncStatus.live;
    }
  }

  @override
  Stream<SyncStatusState> get state => _controller.stream;

  @override
  Future<void> start() async {
    if (_networkSub != null) {
      return;
    }
    _networkSub = _network.statusChanges.listen((status) async {
      _lastNetwork = status;
      await _refreshAndEmit();
    });
    _queueSub = _queueChanges.changes.listen((items) {
      _lastPendingCount =
          items.where((i) => i.status == SyncQueueStatus.pending).length;
      // Any in-progress item means a sync run is actively flushing right now
      // (the worker marks items in_progress before pushing, Task 5.2). This
      // drives the status bar's subtle progress indicator (Task 5.4).
      _isSyncing = items.any((i) => i.status == SyncQueueStatus.inProgress);
      _recompute();
    });
    await refresh();
  }

  @override
  Future<void> refresh() async {
    _lastNetwork = await _network.currentStatus();
    await _refreshAndEmit();
  }

  @override
  Future<void> close() async {
    await _networkSub?.cancel();
    await _queueSub?.cancel();
    await _controller.close();
  }

  Future<void> _refreshAndEmit() async {
    // Re-read the FULL queue snapshot (not just pending) so network-driven
    // emissions carry a FRESH isSyncing flag too — otherwise a status emitted
    // from a network change could keep a stale syncing=true from before the
    // worker's final snapshot landed (code-review finding, Task 5.4).
    final all = await _queueRepository.getAll();
    _lastPendingCount =
        all.where((i) => i.status == SyncQueueStatus.pending).length;
    _isSyncing = all.any((i) => i.status == SyncQueueStatus.inProgress);
    _recompute();
  }

  void _recompute() {
    // A sync run is "draining" while the queue still has pending or
    // in-progress items. When draining flips to not-draining (queue fully
    // flushed) while online, the run just completed — stamp lastSyncAt so
    // the status bar can show "Last synced: …" (Task 5.4). The clock is
    // injectable so tests assert the exact timestamp.
    final isDraining = _lastPendingCount > 0 || _isSyncing;
    if (_wasDraining && !isDraining && _lastNetwork == NetworkStatus.online) {
      _lastSyncAt = _clock();
    }
    _wasDraining = isDraining;

    _controller.add(
      SyncStatusState(
        status: derive(_lastNetwork, _lastPendingCount),
        pendingCount: _lastPendingCount,
        lastSyncAt: _lastSyncAt,
        isSyncing: _isSyncing,
      ),
    );
  }
}
