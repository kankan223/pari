import 'dart:async';
import 'dart:math';

import '../../repository/domain/exponential_backoff.dart';
import 'relay_heartbeat.dart';
import 'relay_socket.dart';
import 'relay_wire.dart';

/// Connection lifecycle phase of the relay client (Task 6.4).
enum RelayConnectionPhase {
  /// Never started, or stopped by the caller.
  disconnected,

  /// TCP/TLS handshake or auth in progress.
  connecting,

  /// Authenticated and the read loop is live.
  connected,

  /// A transient failure — a reconnect is scheduled with backoff.
  reconnecting,

  /// The relay rejected the access token. Terminal: the client will NOT
  /// retry (a rejected token cannot succeed by retrying) — the caller must
  /// re-authenticate and start a fresh client.
  authFailed,
}

/// Realtime relay client (Task 6.4).
///
/// Orchestrates one WebSocket session with the Go relay (`GET /v1/relay/ws`,
/// Task 4.4):
///
///  1. **First-frame auth** — the access token and device id are sent in the
///     AUTH frame BODY immediately after connect, never in the URL (query
///     strings are logged by proxies).
///  2. **Read loop** — decodes every inbound frame; envelopes are forwarded
///     to [envelopes] and automatically acked back to the relay (enabling
///     offline-queue purge).
///  3. **Dead-connection detection** — the real socket (transport-level
///     heartbeat, [RelaySocket.hasTransportHeartbeat]) has dart:io close it
///     when the relay stops answering protocol pings (mirroring the relay's
///     25s ping / 10s pong); sockets without transport liveness get an
///     app-level [RelayHeartbeat] watchdog over [staleAfter] instead.
///  4. **Reconnect** — transient failures (including a drop during the auth
///     handshake before any auth_ack arrived) reconnect with the shared
///     [ExponentialBackoff] policy (jittered, Task 5.2); an explicit auth
///     rejection ([RelayConnectionPhase.authFailed]) is terminal and never
///     retried.
///
/// SECURITY CHECKPOINTS:
///  - The JWT exists only in the first frame body — never in the URL.
///  - [sendEnvelope] validates the msg id (UUID v4) and recipient (64-hex
///    blind hash) BEFORE the bytes leave the device; PII-shaped values are
///    rejected at the port boundary and can never reach the wire or a Redis
///    key.
///  - Envelope ciphertext is opaque: the client never decrypts, inspects, or
///    logs it.
class RelayClient {
  final String _accessToken;
  final String _deviceId;
  final String _url;
  final RelaySocketConnector _connector;
  final Duration _staleAfter;
  final ExponentialBackoff _backoff;
  final Timer Function(Duration, void Function()) _createTimer;
  final DateTime Function() _clock;
  final Random _random;

  final _envelopes = StreamController<RelayEnvelope>.broadcast();
  final _phases = StreamController<RelayConnectionPhase>.broadcast();
  final _typingIndicators = StreamController<RelayTypingFrame>.broadcast();
  final _readReceipts = StreamController<RelayReadReceiptFrame>.broadcast();

  RelaySocket? _socket;
  StreamSubscription<String>? _framesSub;
  RelayHeartbeat? _heartbeat;
  Timer? _reconnectTimer;
  bool _stopped = true;
  bool _authOk = false;

  /// Set when the relay explicitly rejects the token (auth_ack:false). The
  /// subsequent policy-violation close must NOT be treated as a transient
  /// drop — auth failure is terminal and never retried.
  bool _authRejected = false;
  int _reconnectAttempt = 0;
  int _generation = 0;

  /// [staleAfter] is the silence window after which the watchdog fires
  /// (default 30s — comfortably above the relay's 25s ping so healthy
  /// connections never trip it).
  RelayClient({
    required String accessToken,
    required String deviceId,
    required String url,
    required RelaySocketConnector connector,
    Duration? staleAfter,
    ExponentialBackoff? backoff,
    Timer Function(Duration, void Function())? createTimer,
    DateTime Function()? clock,
    Random? random,
  })  : _accessToken = accessToken,
        _deviceId = deviceId,
        _url = url,
        _connector = connector,
        _staleAfter = staleAfter ?? const Duration(seconds: 30),
        _backoff = backoff ?? const ExponentialBackoff(),
        _createTimer = createTimer ?? Timer.new,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random();

  /// Received envelopes (broadcast — UI layers subscribe here).
  Stream<RelayEnvelope> get envelopes => _envelopes.stream;

  /// Connection lifecycle changes.
  Stream<RelayConnectionPhase> get phases => _phases.stream;

  /// Incoming typing indicators from other users.
  Stream<RelayTypingFrame> get typingIndicators => _typingIndicators.stream;

  /// Incoming read receipts from other users.
  Stream<RelayReadReceiptFrame> get readReceipts => _readReceipts.stream;

  /// Current lifecycle phase.
  RelayConnectionPhase get phase => _phase;
  RelayConnectionPhase _phase = RelayConnectionPhase.disconnected;

  void _setPhase(RelayConnectionPhase phase) {
    _phase = phase;
    _phases.add(phase);
  }

  /// Sends one envelope. Validates the msg id (UUID v4) and recipient
  /// (64-hex blind hash) — invalid values throw [ArgumentError] and never
  /// reach the wire.
  ///
  /// SECURITY CHECKPOINT: the sender hash is NOT sent by the client at all —
  /// the relay server overrides sender identity from the authenticated
  /// token, so client-side spoofing is structurally impossible.
  Future<void> sendEnvelope(RelayEnvelope envelope) {
    if (!RelayEnvelope.isValidMsgId(envelope.msgId)) {
      throw ArgumentError('msgId must be a UUID v4');
    }
    if (!RelayEnvelope.isValidBlindHash(envelope.recipientHash)) {
      throw ArgumentError('recipientHash must be a 64-hex blind hash');
    }
    final socket = _socket;
    if (socket == null || !_authOk) {
      throw StateError('relay client is not connected');
    }
    return socket.send(RelayEnvelopeFrame(envelope).encode());
  }

  /// Sends a typing indicator to [recipientHash].
  Future<void> sendTyping(String recipientHash, bool isTyping) {
    final socket = _socket;
    if (socket == null || !_authOk) {
      throw StateError('relay client is not connected');
    }
    return socket.send(RelayTypingFrame(
      recipientHash: recipientHash,
      isTyping: isTyping,
    ).encode());
  }

  /// Sends a read receipt to [senderHash] indicating we've seen up to [lastMsgId].
  Future<void> sendReadReceipt(String senderHash, String lastMsgId) {
    final socket = _socket;
    if (socket == null || !_authOk) {
      throw StateError('relay client is not connected');
    }
    return socket.send(RelayReadReceiptFrame(
      senderHash: senderHash,
      lastMsgId: lastMsgId,
    ).encode());
  }

  /// Acknowledges delivery of [msgId]. Called automatically for inbound
  /// envelopes; exposed for explicit ack flows (e.g. after local decryption).
  Future<void> ack(String msgId) {
    final socket = _socket;
    if (socket == null || !_authOk) {
      throw StateError('relay client is not connected');
    }
    return socket.send(RelayAckFrame(msgId).encode());
  }

  /// Starts the client: connects and authenticates. Idempotent.
  void start() {
    if (!_stopped) {
      return;
    }
    _stopped = false;
    _reconnectAttempt = 0;
    _connect();
  }

  /// Tears the connection down and cancels any scheduled reconnect.
  Future<void> stop() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _generation++;
    await _teardownSocket();
    _setPhase(RelayConnectionPhase.disconnected);
  }

  void _connect() {
    if (_stopped) {
      return;
    }
    final generation = ++_generation;
    _setPhase(RelayConnectionPhase.connecting);
    _authOk = false;
    _authRejected = false;

    // A connector failure (DNS/TCP/TLS) surfaces as an error on frames;
    // schedule a reconnect rather than throwing into the caller.
    unawaited(_connector.connect(_url).then((socket) {
      if (_stopped || generation != _generation) {
        unawaited(socket.close());
        return;
      }
      _attachSession(generation, socket);
    }).catchError((Object _) {
      if (_stopped || generation != _generation) {
        return;
      }
      _scheduleReconnect();
    }));
  }

  void _attachSession(int generation, RelaySocket socket) {
    _socket = socket;
    // App-level heartbeat watchdog: only for sockets WITHOUT transport-level
    // liveness. The real socket detects dead connections via protocol
    // ping/pong (dart:io closes when pongs stop), so the data-frame watchdog
    // would be redundant — and worse, it would FALSELY fire on healthy idle
    // connections, because the relay's own protocol pings never surface as
    // data frames.
    if (!socket.hasTransportHeartbeat) {
      _heartbeat = _buildHeartbeat(generation, socket);
      _heartbeat!.start();
    }

    _framesSub = socket.frames.listen(
      (text) {
        if (_stopped || generation != _generation) {
          return;
        }
        _heartbeat?.notifyActivity();
        final frame = RelayFrame.decode(text);
        if (frame == null) {
          return; // unknown/foreign frame — dropped, connection stays
        }
        _handleFrame(generation, socket, frame);
      },
      onError: (Object _) {
        // Transport-level failure — reconnect with backoff.
        if (_stopped || generation != _generation) {
          return;
        }
        _endSession(generation, reconnect: true);
      },
      onDone: () {
        if (_stopped || generation != _generation) {
          return;
        }
        // Remote closed. A policy-violation close follows an auth rejection
        // (the relay sends auth_ack:false then closes) — we surface the
        // rejection as terminal. Any OTHER close — including a drop during
        // the auth handshake before any auth_ack arrived (network blip,
        // relay restart) — is a transient transport failure and must be
        // retried with backoff.
        _endSession(generation, reconnect: _authRejected ? false : true);
      },
    );

    // First frame MUST be auth (relay requirement).
    unawaited(socket.send(
      RelayAuthFrame(accessToken: _accessToken, deviceId: _deviceId).encode(),
    ));
    // Surface transport termination (fatal errors) so the caller can react.
    unawaited(socket.done.then((_) {}).catchError((Object _) {
      if (_stopped || generation != _generation) {
        return;
      }
      _endSession(generation, reconnect: true);
    }));
  }

  void _handleFrame(int generation, RelaySocket socket, RelayFrame frame) {
    switch (frame) {
      case RelayAuthAckFrame(:final authenticated):
        if (!authenticated) {
          // The relay explicitly rejected the token. Terminal: retrying the
          // same token cannot succeed. Track it so the subsequent close
          // (StatusPolicyViolation) is NOT treated as a transient drop.
          _authRejected = true;
          _setPhase(RelayConnectionPhase.authFailed);
          _endSession(generation, reconnect: false);
          return;
        }
        _authOk = true;
        _reconnectAttempt = 0; // healthy — reset the retry ladder
        _setPhase(RelayConnectionPhase.connected);
      case RelayEnvelopeFrame(:final envelope):
        _envelopes.add(envelope);
        // Auto-ack: the message is now durably handled client-side; this
        // purges it from the relay's offline queue (Task 4.4).
        unawaited(socket.send(RelayAckFrame(envelope.msgId).encode()));
      case RelayTypingFrame(:final recipientHash, :final isTyping):
        // Typing indicators from other users — surface to the UI.
        _typingIndicators.add(RelayTypingFrame(
          recipientHash: recipientHash,
          isTyping: isTyping,
        ));
      case RelayReadReceiptFrame(:final senderHash, :final lastMsgId):
        // Read receipts from other users — surface to the UI.
        _readReceipts.add(RelayReadReceiptFrame(
          senderHash: senderHash,
          lastMsgId: lastMsgId,
        ));
      case RelayAckFrame():
      case RelayErrorFrame():
      case RelayAuthFrame():
        break; // server never sends these; ignore defensively
    }
  }

  RelayHeartbeat _buildHeartbeat(int generation, RelaySocket socket) {
    return RelayHeartbeat(
      staleAfter: _staleAfter,
      clock: _clock,
      createTimer: _createTimer,
      onStale: () {
        // A silent connection is dead — tear down and reconnect.
        if (_stopped || generation != _generation) {
          return;
        }
        unawaited(socket.close());
        _endSession(generation, reconnect: true);
      },
    );
  }

  void _endSession(int generation, {required bool reconnect}) {
    if (_stopped || generation != _generation) {
      return;
    }
    _generation++; // invalidate this session
    _heartbeat?.stop();
    _heartbeat = null;
    unawaited(_framesSub?.cancel());
    _framesSub = null;
    _socket = null;
    if (reconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_stopped) {
      return;
    }
    _setPhase(RelayConnectionPhase.reconnecting);
    final delay = _backoff.delayForRetryWithJitter(
      _reconnectAttempt + 1,
      random: _random,
    );
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = _createTimer(delay, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  Future<void> _teardownSocket() async {
    _heartbeat?.stop();
    _heartbeat = null;
    await _framesSub?.cancel();
    _framesSub = null;
    await _socket?.close();
    _socket = null;
  }

  /// Releases internal stream controllers. Call on app teardown.
  Future<void> dispose() async {
    await stop();
    await _envelopes.close();
    await _phases.close();
    await _typingIndicators.close();
    await _readReceipts.close();
  }
}
