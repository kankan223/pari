import 'dart:async';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/relay_socket.dart';

/// [RelaySocket] backed by `web_socket_channel`'s [IOWebSocketChannel]
/// (Task 6.4).
///
/// The channel is created LAZILY on first frame listen (matching
/// `web_socket_channel`'s contract: `ready` only completes once the
/// connection is established). Failures surface as a stream error so the
/// [RelayClient] can treat them uniformly as transport failures and
/// reconnect with backoff.
///
/// TRANSPORT-LEVEL HEARTBEAT: [pingInterval] is passed to the channel so
/// dart:io sends protocol pings and CLOSES the connection when the relay
/// stops answering — the [RelayClient] then observes the disconnect and
/// reconnects. This mirrors the Go relay's 25s protocol ping (Task 4.4) and
/// is the correct dead-connection detector for this transport: the relay's
/// pings are control frames that never surface as data frames, so an
/// app-level data-frame watchdog would falsely fire on healthy idle
/// connections. [hasTransportHeartbeat] reports this capability.
///
/// SECURITY CHECKPOINT: the socket is a dumb byte carrier — the access token
/// is never part of the URL (the caller holds it in the auth frame body),
/// and frame payloads are never logged.
class WebSocketRelaySocket implements RelaySocket {
  final String _url;
  final Duration _pingInterval;
  WebSocketChannel? _channel;
  StreamController<String>? _controller;
  final _done = Completer<void>();
  bool _closed = false;

  WebSocketRelaySocket(this._url, {Duration pingInterval = _defaultPing})
      : _pingInterval = pingInterval;

  /// 20s — comfortably inside the relay's 25s ping cadence, so a relay that
  /// stops ponging is detected within one interval.
  static const _defaultPing = Duration(seconds: 20);

  @override
  bool get hasTransportHeartbeat => true;

  @override
  Stream<String> get frames {
    _ensureChannel();
    return _controller!.stream;
  }

  void _ensureChannel() {
    if (_controller != null) {
      return;
    }
    final channel = IOWebSocketChannel.connect(
      _url,
      // Protocol-level ping/pong: dart:io closes the connection when no
      // pong arrives within the interval (dead relay / middlebox kill), and
      // the client's read loop observes the disconnect and reconnects.
      pingInterval: _pingInterval,
    );
    _channel = channel;
    final controller = StreamController<String>();
    _controller = controller;

    // The channel's native stream is single-subscription; we bridge it into
    // the controller. Completion/errors propagate so the read loop sees the
    // disconnect.
    channel.stream.listen(
      (dynamic data) {
        if (data is String) {
          controller.add(data);
        }
      },
      onError: (Object e) {
        controller.addError(e);
        _finish();
      },
      onDone: () {
        controller.close();
        _finish();
      },
    );

    // TCP/TLS handshake failures surface on `ready` (not the stream) before
    // any frame arrives — propagate them so the RelayClient treats them as
    // transport failures and reconnects with backoff.
    unawaited(channel.ready.catchError((Object e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
      _finish();
    }));
  }

  void _finish() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> send(String wireJson) {
    _ensureChannel();
    final channel = _channel;
    if (channel == null) {
      throw StateError('relay socket is closed');
    }
    // sink.add does not complete a future; a returned Future that completes
    // immediately is acceptable for a fire-and-forget control frame, but we
    // surface send failures through the done completer by listening for
    // channel errors.
    channel.sink.add(wireJson);
    return Future.value();
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    final channel = _channel;
    if (channel != null) {
      await channel.sink.close();
    }
    _finish();
    await _controller?.close();
    _controller = null;
  }
}

/// Creates [WebSocketRelaySocket]s for a relay endpoint.
class WebSocketRelaySocketConnector implements RelaySocketConnector {
  const WebSocketRelaySocketConnector();

  @override
  Future<RelaySocket> connect(String url) async => WebSocketRelaySocket(url);
}
