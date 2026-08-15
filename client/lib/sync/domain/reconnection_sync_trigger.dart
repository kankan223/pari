import 'dart:async';

import '../../repository/domain/local_first_repository.dart';
import 'network_state.dart';
import 'sync_worker.dart';

/// Fires a background sync when the device reconnects (Task 3.4).
///
/// Subscribes to [NetworkInfoProvider.statusChanges] and invokes the
/// [SyncWorker] exactly once per offline→online transition. This is the
/// "sync trigger on network reconnection" required by the master plan.
///
/// SECURITY CHECKPOINT (Task 3.4): the trigger ONLY starts a sync when the
/// network has actually returned — it never forces sync while offline, so
/// the offline-first architecture is preserved.
class ReconnectionSyncTrigger {
  final NetworkInfoProvider _network;
  final SyncWorker _worker;

  const ReconnectionSyncTrigger({
    required NetworkInfoProvider network,
    required SyncWorker worker,
  })  : _network = network,
        _worker = worker;

  /// Starts listening for reconnections and returns the subscription so the
  /// caller can cancel it (e.g. on app teardown).
  ///
  /// On the FIRST status change, sync runs if the device is online. After
  /// that, sync runs only on transitions INTO online from a non-online
  /// state (offline or metered).
  StreamSubscription<NetworkStatus> start() {
    NetworkStatus? last;
    return _network.statusChanges.listen((status) {
      final becameOnline =
          status == NetworkStatus.online && last != NetworkStatus.online;
      last = status;
      if (becameOnline) {
        // Fire-and-forget, but crash-safe: a background sync failure must
        // never become an unhandled async exception. Failed items stay
        // pending in the queue and are retried on the next reconnection
        // (offline-first retry contract).
        unawaited(_worker.runOnce().catchError((Object _) {
          // Intentionally ignored — the queue retains the items. A thrown
          // error is reported as zero pushed/failed so the drain is not
          // misinterpreted, and the items are retried next reconnection.
          return const SyncResult(pushed: 0, failed: 0);
        }));
      }
    });
  }
}
