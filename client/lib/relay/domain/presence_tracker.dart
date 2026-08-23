import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Tracks online/offline presence of other users on the platform.
///
/// Polls the relay's `/v1/relay/presence` endpoint periodically to discover
/// which blind_hash_ids are currently connected. Exposes a stream of
/// presence snapshots so the UI can show online/offline indicators.
///
/// SECURITY CHECKPOINT: only 64-hex blind hash IDs are tracked — no
/// usernames, phone numbers, or PII. The polling URL is the same relay
/// already trusted for WebSocket traffic.
class PresenceTracker {
  final String _relayUrl;
  final String Function() _tokenProvider;
  final Duration _pollInterval;
  final http.Client _httpClient;

  Timer? _timer;
  final _controller = StreamController<PresenceSnapshot>.broadcast();
  Set<String> _currentlyOnline = {};

  PresenceTracker({
    required String relayUrl,
    required String Function() tokenProvider,
    Duration? pollInterval,
    http.Client? httpClient,
  })  : _relayUrl = relayUrl,
        _tokenProvider = tokenProvider,
        _pollInterval = pollInterval ?? const Duration(seconds: 15),
        _httpClient = httpClient ?? http.Client();

  /// Stream of presence snapshots (broadcast). Each emission contains
  /// the current set of online blind hash IDs.
  Stream<PresenceSnapshot> get snapshots => _controller.stream;

  /// Current set of online users (synchronous snapshot).
  Set<String> get onlineUsers => Set.unmodifiable(_currentlyOnline);

  /// Whether [blindHashId] is currently online.
  bool isOnline(String blindHashId) => _currentlyOnline.contains(blindHashId);

  /// Start periodic presence polling. Idempotent.
  void start() {
    if (_timer != null) return;
    // Immediate first poll.
    _poll();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  /// Stop polling and close the stream.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _controller.close();
  }

  Future<void> _poll() async {
    try {
      final token = _tokenProvider();
      if (token.isEmpty) return;

      final url = Uri.parse('$_relayUrl/v1/relay/presence');
      final response = await _httpClient
          .get(url, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final onlineList = body['online'] as List<Object?>? ?? [];
      final onlineSet = Set<String>.from(
        onlineList.whereType<String>(),
      );

      _currentlyOnline = onlineSet;
      if (!_controller.isClosed) {
        _controller.add(PresenceSnapshot(
          onlineUsers: Set.unmodifiable(onlineSet),
          timestamp: DateTime.now(),
        ));
      }
    } catch (_) {
      // Network errors are swallowed — presence is best-effort.
    }
  }
}

/// A point-in-time snapshot of online users.
class PresenceSnapshot {
  final Set<String> onlineUsers;
  final DateTime timestamp;

  const PresenceSnapshot({
    required this.onlineUsers,
    required this.timestamp,
  });
}
