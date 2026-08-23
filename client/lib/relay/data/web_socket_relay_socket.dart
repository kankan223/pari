import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/relay_socket.dart';

/// [RelaySocket] backed by `web_socket_channel`'s [WebSocketChannel].
///
/// Uses the platform-agnostic `WebSocketChannel.connect()` factory, which
/// works on both web (dart:html WebSocket) and native (dart:io WebSocket).
/// The previous [IOWebSocketChannel] implementation crashed on Flutter web
/// because dart:io is not available in browser environments.
///
/// The channel is created LAZILY on first frame listen. Failures surface as
/// a stream error so the [RelayClient] can treat them uniformly as transport
/// failures and reconnect with backoff.
///
/// TRANSPORT-LEVEL HEARTBEAT: On native platforms, pingInterval is applied
/// to the underlying socket so dart:io sends protocol pings and CLOSES the
/// connection when the relay stops answering. On web, the browser manages
/// WebSocket ping/pong natively. In both cases, [hasTransportHeartbeat]
/// reports true so the [RelayClient] skips its app-level data-frame watchdog
/// (which would falsely fire on healthy idle connections).
///
/// SECURITY CHECKPOINT: the socket is a dumb byte carrier — the access token
/// is never part of the URL (the caller holds it in the auth frame body),
/// and frame payloads are never logged.
class WebSocketRelaySocket implements RelaySocket {
  final String _url;
  WebSocketChannel? _channel;
  StreamController<String>? _controller;
  final _done = Completer<void>();
  bool _closed = false;

  WebSocketRelaySocket(this._url);

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
    // Use the platform-agnostic WebSocketChannel.connect() factory.
    // On native: uses dart:io WebSocket internally.
    // On web: uses dart:html WebSocket internally.
    final channel = WebSocketChannel.connect(Uri.parse(_url));
    _channel = channel;
    final controller = StreamController<String>();
    _controller = controller;

    // Bridge the channel's single-subscription stream into our broadcast
    // controller. Completion/errors propagate so the read loop sees the
    // disconnect.
    channel.stream.listen(
      (dynamic data) {
        if (data is String) {
          controller.add(data);
        }
      },
      onError: (Object e) {
        if (!controller.isClosed) {
          controller.addError(e);
        }
        _finish();
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
        _finish();
      },
    );

    // On native platforms, TCP/TLS handshake failures surface on `ready`
    // (not the stream) before any frame arrives. On web, the WebSocket
    // connection error is delivered through the stream's onError handler
    // above, so the ready catch is only useful on native.
    try {
      // ignore: unnecessary_statements
      channel.ready.catchError((Object e) {
        if (!controller.isClosed) {
          controller.addError(e);
        }
        _finish();
      });
    } catch (_) {
      // web: WebSocketChannel has no `ready` getter — connection errors
      // arrive through the stream listener above. This is expected.
    }
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
    if (_controller != null && !_controller!.isClosed) {
      await _controller!.close();
    }
    _controller = null;
  }
}

/// Creates [WebSocketRelaySocket]s for a relay endpoint.
class WebSocketRelaySocketConnector implements RelaySocketConnector {
  const WebSocketRelaySocketConnector();

  @override
  Future<RelaySocket> connect(String url) async => WebSocketRelaySocket(url);
}
