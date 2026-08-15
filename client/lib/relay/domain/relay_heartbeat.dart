import 'dart:async';

/// Heartbeat watchdog (Task 6.4, mirrors the relay's 25s ping / 10s pong).
///
/// The Go relay pings the client every 25s and drops the peer when no pong
/// arrives within 10s (coder/websocket handles the pong on our side, so a
/// healthy connection always sees traffic). This watchdog detects the
/// INVERSE failure: a connection that has gone silent from the relay's side
/// (middlebox kill, relay crash without a close frame). If no frame arrives
/// within [staleAfter], it fires [onStale] so the caller can tear the
/// connection down and reconnect.
///
/// Clock- and timer-injectable for deterministic `fake_async` tests.
class RelayHeartbeat {
  final Duration staleAfter;

  /// A clock for "now" — injectable for deterministic tests.
  final DateTime Function() clock;

  /// Creates the interval timer driving checks — injectable for tests.
  final Timer Function(Duration, void Function()) createTimer;

  final void Function() onStale;

  RelayHeartbeat({
    this.staleAfter = const Duration(seconds: 30),
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? createTimer,
    required this.onStale,
  })  : clock = clock ?? DateTime.now,
        createTimer = createTimer ?? Timer.new;

  Timer? _timer;
  DateTime? _lastFrameAt;
  bool _stopped = false;

  /// Starts the watchdog. Idempotent.
  void start() {
    if (_timer != null) {
      return;
    }
    _lastFrameAt = clock();
    _timer = createTimer(const Duration(seconds: 1), _tick);
  }

  /// Records inbound traffic — the watchdog considers the connection alive.
  void notifyActivity() {
    _lastFrameAt = clock();
  }

  void _tick() {
    if (_stopped) {
      return;
    }
    final last = _lastFrameAt;
    if (last != null && clock().difference(last) >= staleAfter) {
      _stopped = true;
      _timer?.cancel();
      _timer = null;
      onStale();
      return;
    }
    _timer = createTimer(const Duration(seconds: 1), _tick);
  }

  /// Stops the watchdog. Idempotent.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }
}
