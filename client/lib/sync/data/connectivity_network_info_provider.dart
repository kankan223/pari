import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../domain/network_state.dart';

/// [NetworkInfoProvider] backed by `connectivity_plus` (data layer).
///
/// NOTE: `connectivity_plus` requires platform channels (Android/iOS/etc.);
/// this implementation is compile-verified here. Unit tests exercise the
/// domain logic (trigger transitions, chunking, worker batching) with a
/// scripted fake provider instead.
///
/// Mapping: `none` → offline, `mobile` → metered, everything else (wifi,
/// ethernet, vpn, bluetooth, other) → online.
class ConnectivityNetworkInfoProvider implements NetworkInfoProvider {
  final Connectivity _connectivity;

  ConnectivityNetworkInfoProvider({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  @override
  Future<NetworkStatus> currentStatus() async {
    final result = await _connectivity.checkConnectivity();
    return _map(result);
  }

  @override
  Stream<NetworkStatus> get statusChanges =>
      _connectivity.onConnectivityChanged.map(_map);

  static NetworkStatus _map(ConnectivityResult result) => map(result);

  /// Public mapping for tests: connectivity_plus result → [NetworkStatus].
  static NetworkStatus map(ConnectivityResult result) => switch (result) {
        ConnectivityResult.none => NetworkStatus.offline,
        ConnectivityResult.mobile => NetworkStatus.metered,
        ConnectivityResult.wifi ||
        ConnectivityResult.ethernet ||
        ConnectivityResult.vpn ||
        ConnectivityResult.bluetooth ||
        ConnectivityResult.other =>
          NetworkStatus.online,
      };
}
