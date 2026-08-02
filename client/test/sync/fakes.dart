import 'dart:async';

import 'package:civic_commons/sync/domain/network_state.dart';
import 'package:civic_commons/sync/domain/sync_worker.dart';
import 'package:civic_commons/repository/domain/local_first_repository.dart';

/// Scripted [NetworkInfoProvider] fake for unit tests.
class FakeNetworkInfoProvider implements NetworkInfoProvider {
  final StreamController<NetworkStatus> _controller =
      StreamController<NetworkStatus>.broadcast();
  NetworkStatus current = NetworkStatus.online;

  @override
  Future<NetworkStatus> currentStatus() async => current;

  @override
  Stream<NetworkStatus> get statusChanges => _controller.stream;

  /// Emits a status change to subscribers.
  void emit(NetworkStatus status) {
    current = status;
    _controller.add(status);
  }

  void dispose() => _controller.close();
}

/// Recording [SyncWorker] fake — counts invocations and records results.
class RecordingSyncWorker implements SyncWorker {
  final List<SyncResult> runs = [];
  SyncResult nextResult = const SyncResult(pushed: 0, failed: 0);

  @override
  Future<SyncResult> runOnce() async {
    runs.add(nextResult);
    return nextResult;
  }

  int get runCount => runs.length;
}
