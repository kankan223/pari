import 'dart:async';

import 'network_state.dart';

/// Decorates a [NetworkInfoProvider] with a debounced [statusChanges] stream
/// (Task 5.1).
///
/// Rapid connectivity flapping (Wi-Fi ↔ cellular handoffs, airplane-mode
/// toggles) collapses into a single emission after [debounce] of quiet. The
/// LAST status observed during the window wins — so a brief offline blip
/// inside an otherwise-online window never fires a spurious reconnection
/// sync, and a genuine offline transition is not lost.
///
/// [currentStatus] passes through unchanged (one-shot reads are already
/// authoritative). Only the change stream is debounced.
///
/// SECURITY CHECKPOINT (Task 5.1): debouncing is pure timing logic — no
/// network state ever leaves the device, and the debounced stream carries
/// the same [NetworkStatus] values (never IPs, never fingerprints).
class DebouncedNetworkInfoProvider implements NetworkInfoProvider {
  final NetworkInfoProvider _inner;
  final Duration debounce;

  const DebouncedNetworkInfoProvider(
    this._inner, {
    this.debounce = const Duration(milliseconds: 500),
  });

  @override
  Future<NetworkStatus> currentStatus() => _inner.currentStatus();

  @override
  Stream<NetworkStatus> get statusChanges {
    late StreamController<NetworkStatus> controller;
    StreamSubscription<NetworkStatus>? innerSub;
    Timer? timer;
    NetworkStatus? pending;

    controller = StreamController<NetworkStatus>(
      onListen: () {
        innerSub = _inner.statusChanges.listen(
          (status) {
            // Remember the latest status; (re)start the quiet window.
            pending = status;
            timer?.cancel();
            timer = Timer(debounce, () {
              final toEmit = pending;
              pending = null;
              if (!controller.isClosed && toEmit != null) {
                controller.add(toEmit);
              }
            });
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            if (!controller.isClosed) {
              controller.close();
            }
          },
        );
      },
      onCancel: () {
        timer?.cancel();
        innerSub?.cancel();
        if (!controller.isClosed) {
          controller.close();
        }
      },
    );

    return controller.stream;
  }
}
