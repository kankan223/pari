import 'dart:async';
import 'dart:math';

/// Optional keepalive traffic generator (Task 6.4).
///
/// Some NATS-degraded or aggressively-proxied deployments drop WebSockets
/// that carry no data traffic even when control pings flow. This OPT-IN
/// generator sends a tiny, non-sensitive envelope every [interval] while the
/// caller's connection is up, keeping the transport warm.
///
/// SECURITY CHECKPOINT: the generated envelope carries a random UUID v4 msg
/// id (the caller then self-routes it — the relay delivers it back to the
/// caller's own queue and the client acks it, purging it). No PII, no real
/// payloads, no decrypted content ever touches the wire. Disabled by
/// default — the relay's own heartbeat is the primary liveness mechanism.
class DummyTrafficGenerator {
  final Duration interval;
  final String blindHashId;
  final String deviceId;
  final void Function(String msgId) send;
  final Timer Function(Duration, void Function()) createTimer;
  final Random random;

  DummyTrafficGenerator({
    this.interval = const Duration(seconds: 15),
    required this.blindHashId,
    required this.deviceId,
    required this.send,
    Timer Function(Duration, void Function())? createTimer,
    Random? random,
  })  : createTimer = createTimer ?? Timer.new,
        random = random ?? Random.secure();

  Timer? _timer;

  /// Starts emitting keepalive envelopes. Idempotent.
  void start() {
    if (_timer != null) {
      return;
    }
    _timer = createTimer(interval, _tick);
  }

  void _tick() {
    // A random UUID v4 msg id — no sequence numbers, no wall-clock
    // timestamps, nothing that could fingerprint the device or correlate
    // traffic.
    send(_uuidV4());
    _timer = createTimer(interval, _tick);
  }

  /// Stops emitting. Idempotent.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
