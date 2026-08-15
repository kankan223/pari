import 'dart:async';

/// A live relay WebSocket connection (port, Task 6.4).
///
/// Implemented by [WebSocketRelaySocket] (data layer) over
/// `web_socket_channel`; tests inject a scripted fake. The socket is a dumb
/// byte carrier: it knows nothing about auth, heartbeats, or routing — it
/// just delivers decoded frames and sends encoded ones.
///
/// A socket MAY provide transport-level liveness ([hasTransportHeartbeat]):
/// the real WebSocket sets `pingInterval` so the underlying dart:io
/// connection closes itself when pongs stop arriving — the client then
/// observes a disconnect and reconnects, without needing an app-level
/// watchdog.
abstract class RelaySocket {
  /// The stream of raw wire JSON texts received from the relay.
  ///
  /// This is a SINGLE-SUBSCRIPTION stream: exactly one reader (the
  /// [RelayClient] read loop) may listen. The concrete socket also monitors
  /// the underlying channel for disconnects and closes this stream when the
  /// remote dies.
  Stream<String> get frames;

  /// Sends one raw wire JSON text. Completes when the byte is handed to the
  /// transport; errors surface on [done] for fatal failures.
  Future<void> send(String wireJson);

  /// Completes when the connection terminates (any reason). The error, when
  /// non-null, is a transport-level failure.
  Future<void> get done;

  /// Closes the connection.
  Future<void> close();

  /// Whether the transport itself keeps the connection alive with protocol
  /// ping/pong (e.g. [WebSocketRelaySocket] sets `pingInterval` so dart:io
  /// closes the socket when the relay stops answering pings).
  ///
  /// When true, the [RelayClient] skips its app-level heartbeat watchdog
  /// (which watches DATA frames — invisible to protocol-level pings — so on
  /// a transport-heartbeat socket it would falsely fire during healthy idle
  /// periods). Dead-connection detection is the transport's job instead.
  bool get hasTransportHeartbeat => false;
}

/// Creates [RelaySocket]s for a relay endpoint (port).
abstract class RelaySocketConnector {
  /// Opens a socket to [url]. The connection is established lazily by the
  /// returned socket on first listen — a failed TCP/TLS handshake surfaces
  /// as a stream error on [RelaySocket.frames].
  Future<RelaySocket> connect(String url);
}
