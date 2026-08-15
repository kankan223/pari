import 'dart:async';

import 'package:civic_commons/relay/domain/relay_socket.dart';
import 'package:civic_commons/relay/domain/relay_wire.dart';

/// A scripted [RelaySocket] for RelayClient lifecycle tests.
///
/// The test drives [pushServerFrame] (what the relay sends) and inspects
/// [sent] (what the client sent). Closing the socket completes [done] and
/// closes the frame stream, mirroring a remote disconnect.
class FakeRelaySocket implements RelaySocket {
  final _controller = StreamController<String>();
  final _done = Completer<void>();

  /// The raw wire JSON the client sent, in order.
  final List<String> sent = [];

  /// The last frame the client sent, decoded (convenience).
  RelayFrame? get lastFrame {
    if (sent.isEmpty) {
      return null;
    }
    return RelayFrame.decode(sent.last);
  }

  /// Every decoded frame the client sent, in order.
  List<RelayFrame> get sentFrames =>
      [for (final s in sent) RelayFrame.decode(s)!];

  /// Whether the test has closed this socket.
  bool closed = false;

  /// Simulates a transport-level heartbeat socket (defaults to false so
  /// tests exercise the app-level watchdog; set true to prove the watchdog
  /// is skipped when the transport handles liveness).
  bool transportHeartbeat = false;

  @override
  bool get hasTransportHeartbeat => transportHeartbeat;

  @override
  Stream<String> get frames => _controller.stream;

  @override
  Future<void> send(String wireJson) async {
    sent.add(wireJson);
  }

  /// Simulates the relay sending a frame to the client.
  void pushServerFrame(RelayFrame frame) {
    _controller.add(frame.encode());
  }

  /// Simulates a remote disconnect. The stream close is fire-and-forget:
  /// the subscription's onDone fires on the next microtask, which is exactly
  /// what the RelayClient's read loop observes as a remote close.
  void disconnect() {
    unawaited(_controller.close());
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  /// Simulates a transport-level failure.
  void fail(Object error) {
    _controller.addError(error);
    if (!_done.isCompleted) {
      _done.complete();
    }
    return;
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    closed = true;
    disconnect();
  }
}

/// A connector that hands out scripted fakes, recording each URL it was
/// asked to connect to.
class FakeRelaySocketConnector implements RelaySocketConnector {
  final List<FakeRelaySocket> sockets = [];
  final List<String> urls = [];
  bool failNext = false;

  /// When true, every socket the connector hands out advertises a
  /// transport-level heartbeat (the app watchdog is skipped).
  bool transportHeartbeat = false;

  FakeRelaySocket get last => sockets.last;

  @override
  Future<RelaySocket> connect(String url) async {
    urls.add(url);
    if (failNext) {
      failNext = false;
      throw StateError('connection refused');
    }
    final socket = FakeRelaySocket()..transportHeartbeat = transportHeartbeat;
    sockets.add(socket);
    return socket;
  }

  /// Convenience: authenticates the CURRENT socket as the relay would,
  /// letting the test move the client to `connected`.
  void authenticateCurrent({bool ok = true}) {
    final ack = RelayAuthAckFrame(
      authenticated: ok,
      blindHashId: ok ? 'a' * 64 : null,
    );
    last.pushServerFrame(ack);
  }
}
