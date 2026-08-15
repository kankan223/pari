import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:civic_commons/relay/data/web_socket_relay_socket.dart';
import 'package:civic_commons/relay/domain/relay_client.dart';
import 'package:civic_commons/relay/domain/relay_wire.dart';
import 'package:civic_commons/repository/domain/exponential_backoff.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

/// Task 6.4 integration: the REAL transport (IOWebSocketChannel) against a
/// REAL `dart:io` WebSocket server speaking the relay wire contract.
///
/// SECURITY CHECKPOINT exercised here: the client's URL carries NO token —
/// the JWT arrives in the first auth frame body, which is exactly what the
/// server asserts below.
void main() {
  final hashA = 'a' * 64;
  final hashB = 'b' * 64;
  const uuid = '4f4a9e10-0b6e-4f9e-9a4c-2e6c7e1a8f0d';

  test('real socket advertises transport-level heartbeat', () {
    final socket = WebSocketRelaySocket('ws://relay.test/v1/relay/ws');
    // The production socket owns dead-connection detection via dart:io
    // pingInterval — the client MUST skip its app-level data-frame watchdog
    // for it (the Go relay's protocol pings never surface as data frames, so
    // an app watchdog would false-fire on healthy idle connections).
    expect(socket.hasTransportHeartbeat, isTrue);
  });

  late HttpServer httpServer;
  late _ConnectionCollector connections;

  /// The query parameters of every upgrade request the server accepted —
  /// asserted empty to prove the token never rides the URL.
  final upgradeQueryParams = <Map<String, String>>[];

  setUp(() async {
    httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    connections = _ConnectionCollector(httpServer.transform(
      StreamTransformer<HttpRequest, IOWebSocketChannel>.fromHandlers(
        handleData: (request, sink) async {
          upgradeQueryParams.add(Map.of(request.uri.queryParameters));
          // The transformer's handleDone closes the sink (linter FP).
          // ignore: close_sinks
          final ws = await WebSocketTransformer.upgrade(request);
          sink.add(IOWebSocketChannel(ws));
        },
        handleError: (error, stack, sink) => sink.addError(error),
        handleDone: (sink) => sink.close(),
      ),
    ));
  });

  tearDown(() async {
    await httpServer.close(force: true);
  });

  Future<IOWebSocketChannel> nextConnection() =>
      connections.next().timeout(const Duration(seconds: 5));

  Future<Map<String, Object?>> readFrame(StreamIterator<dynamic> it) async {
    final ok = await it.moveNext().timeout(const Duration(seconds: 5));
    if (!ok) {
      throw StateError('stream ended before a frame arrived');
    }
    return jsonDecode(it.current as String) as Map<String, Object?>;
  }

  test('full lifecycle over a real socket: auth, envelope, ack', () async {
    final client = RelayClient(
      accessToken: 'jwt.payload.signature',
      deviceId: 'dev-1',
      url: 'ws://127.0.0.1:${httpServer.port}/v1/relay/ws',
      connector: const WebSocketRelaySocketConnector(),
      backoff: const ExponentialBackoff(
        initialDelay: Duration(milliseconds: 10),
      ),
    );

    final envelopeFuture = client.envelopes.first.timeout(
      const Duration(seconds: 5),
    );

    client.start();
    final serverWs = await nextConnection();
    final serverFrames = StreamIterator<dynamic>(serverWs.stream);

    // 1. The FIRST frame must be auth — and it must carry the token in the
    //    body (never a query string; the server asserts the URL is clean).
    expect(upgradeQueryParams, isNotEmpty);
    expect(upgradeQueryParams.single, isEmpty,
        reason: 'the access token must never ride the URL');
    final first = await readFrame(serverFrames);
    expect(first.keys, ['auth']);
    final auth = first['auth']! as Map<String, Object?>;
    expect(auth['access_token'], 'jwt.payload.signature');
    expect(auth['device_id'], 'dev-1');

    // 2. Server authenticates and delivers an envelope.
    serverWs.sink.add(jsonEncode(<String, Object?>{
      'auth_ack': {'authenticated': true, 'blind_hash_id': hashA},
    }));
    serverWs.sink.add(jsonEncode(<String, Object?>{
      'envelope': {
        'msg_id': uuid,
        'sender_hash': hashB,
        'recipient_hash': hashA,
        'ciphertext': base64Encode([7, 8, 9]),
        'sent_at_ms': 123,
        'sender_device_id': 'dev-2',
      },
    }));

    // 3. Client receives the envelope...
    final envelope = await envelopeFuture;
    expect(envelope.ciphertext, [7, 8, 9]);
    expect(envelope.senderHash, hashB);

    // ...and auto-acks it (auth was frame 1, ack is frame 2 from the client).
    final ack = await readFrame(serverFrames);
    expect(ack.keys, ['ack']);
    expect((ack['ack']! as Map<String, Object?>)['msg_id'], uuid);

    // 4. The client sends a valid envelope the server can read.
    unawaited(client.sendEnvelope(RelayEnvelope(
      msgId: uuid,
      senderHash: hashA,
      recipientHash: hashB,
      ciphertext: [1, 2, 3],
      sentAtMs: 456,
      senderDeviceId: 'dev-1',
    )));
    final out = await readFrame(serverFrames);
    expect(out.keys, ['envelope']);
    final outEnv = out['envelope']! as Map<String, Object?>;
    expect(outEnv['recipient_hash'], hashB);
    expect(outEnv['ciphertext'], base64Encode([1, 2, 3]));

    await client.dispose();
    await serverWs.sink.close();
  });

  test('remote close tears the client down and reconnect re-authenticates',
      () async {
    final client = RelayClient(
      accessToken: 'tok',
      deviceId: 'dev-1',
      url: 'ws://127.0.0.1:${httpServer.port}/v1/relay/ws',
      connector: const WebSocketRelaySocketConnector(),
      backoff: const ExponentialBackoff(
        initialDelay: Duration(milliseconds: 10),
      ),
    );

    client.start();
    final serverWs = await nextConnection();
    final serverFrames = StreamIterator<dynamic>(serverWs.stream);
    await readFrame(serverFrames); // consume the auth frame
    serverWs.sink.add(jsonEncode(<String, Object?>{
      'auth_ack': {'authenticated': true, 'blind_hash_id': hashA},
    }));

    // Server drops the connection.
    await serverWs.sink.close();

    // The client reconnects (backoff) — a fresh socket reaches the server.
    final secondWs = await nextConnection();
    final secondFrames = StreamIterator<dynamic>(secondWs.stream);
    final secondFirst = await readFrame(secondFrames);
    expect(secondFirst.keys, ['auth'],
        reason: 'reconnect re-authenticates with a fresh first frame');

    await client.dispose();
    await secondWs.sink.close();
  });
}

/// Collects server-side sockets from the transformer stream so tests can
/// await the next connection without the `async` package's StreamQueue.
class _ConnectionCollector {
  final Stream<IOWebSocketChannel> _source;
  final List<IOWebSocketChannel> _buffered = [];
  final List<Completer<IOWebSocketChannel>> _waiters = [];

  _ConnectionCollector(this._source) {
    _source.listen(
      (socket) {
        if (_waiters.isNotEmpty) {
          _waiters.removeAt(0).complete(socket);
        } else {
          _buffered.add(socket);
        }
      },
      onError: (_) {},
      onDone: () {
        for (final w in _waiters) {
          if (!w.isCompleted) {
            w.completeError(StateError('server closed'));
          }
        }
        _waiters.clear();
      },
    );
  }

  Future<IOWebSocketChannel> next() {
    if (_buffered.isNotEmpty) {
      return Future.value(_buffered.removeAt(0));
    }
    final completer = Completer<IOWebSocketChannel>();
    _waiters.add(completer);
    return completer.future;
  }
}
