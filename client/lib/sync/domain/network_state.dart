import 'dart:async';

/// Connectivity state relevant to sync decisions (Task 3.4; extended in 5.1).
enum NetworkStatus { online, offline, metered }

/// Port for observing network state (domain boundary).
///
/// The concrete implementation wraps `connectivity_plus` (data layer); tests
/// use a scripted fake. The sync layer depends ONLY on this abstract
/// interface — it never touches platform channels itself.
///
/// SECURITY CHECKPOINT (Task 3.4): network state is used solely to decide
/// WHEN to sync — it is never used for fingerprinting, never leaves the
/// device, and is never combined with user data.
abstract class NetworkInfoProvider {
  /// The current network status (one-shot check).
  Future<NetworkStatus> currentStatus();

  /// Stream of network status changes.
  ///
  /// Emits a status whenever the OS reports a connectivity change. The
  /// reconnection trigger subscribes here to fire sync on offline→online
  /// transitions.
  Stream<NetworkStatus> get statusChanges;
}
