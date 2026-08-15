import 'package:civic_commons/relay/domain/dummy_traffic.dart';
import 'package:civic_commons/relay/domain/relay_client.dart';
import 'package:civic_commons/relay/domain/relay_wire.dart';
import 'package:civic_commons/repository/domain/exponential_backoff.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// A deterministic backoff: the jittered delay is always [shortDelay] for
/// retry 1, so reconnects fire after a tiny, elapse-driven wait — without
/// `flushTimers`, which would never drain the client's periodic heartbeat.
class _ImmediateBackoff extends ExponentialBackoff {
  const _ImmediateBackoff()
      : super(initialDelay: const Duration(milliseconds: 5));
}

void main() {
  final hashA = 'a' * 64;
  final hashB = 'b' * 64;
  const uuid = '4f4a9e10-0b6e-4f9e-9a4c-2e6c7e1a8f0d';

  RelayEnvelope envelope([String? recipient]) => RelayEnvelope(
        msgId: uuid,
        senderHash: hashA,
        recipientHash: recipient ?? hashB,
        ciphertext: [1, 2, 3, 4],
        sentAtMs: 1700000000000,
        senderDeviceId: 'dev-1',
      );

  group('RelayClient', () {
    test('authenticates with the token in the FIRST frame body, never the URL',
        () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        final client = RelayClient(
          accessToken: 'jwt.payload.signature',
          deviceId: 'dev-1',
          url: 'wss://relay.example/v1/relay/ws',
          connector: connector,
          backoff: const _ImmediateBackoff(),
        );

        client.start();
        fake.flushMicrotasks();

        expect(connector.urls, ['wss://relay.example/v1/relay/ws']);
        expect(
          connector.urls.single.contains('jwt'),
          isFalse,
          reason: 'the JWT must never appear in the URL',
        );
        expect(connector.urls.single.contains('access_token'), isFalse);

        final socket = connector.last;
        expect(socket.sent, hasLength(1));
        final auth = socket.lastFrame! as RelayAuthFrame;
        expect(auth.accessToken, 'jwt.payload.signature');
        expect(auth.deviceId, 'dev-1');
        // The token IS in the frame body.
        expect(socket.sent.single, contains('jwt.payload.signature'));

        // Auth rejection → authFailed phase, no retry.
        final phases = <RelayConnectionPhase>[];
        client.phases.listen(phases.add);
        connector.authenticateCurrent(ok: false);
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.authFailed);
        expect(phases, contains(RelayConnectionPhase.authFailed));
        // No reconnect scheduled.
        fake.elapse(const Duration(minutes: 1));
        expect(connector.sockets, hasLength(1));

        client.dispose();
      });
    });

    test('reaches connected after a successful auth_ack', () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        final client = RelayClient(
          accessToken: 'tok',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
        );
        final phases = <RelayConnectionPhase>[];
        client.phases.listen(phases.add);

        client.start();
        fake.flushMicrotasks();
        expect(phases, [RelayConnectionPhase.connecting]);

        connector.authenticateCurrent();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.connected);
        expect(phases,
            [RelayConnectionPhase.connecting, RelayConnectionPhase.connected]);

        client.dispose();
      });
    });

    test('forwards inbound envelopes and auto-acks them', () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        final client = RelayClient(
          accessToken: 'tok',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
        );
        final received = <RelayEnvelope>[];
        client.envelopes.listen(received.add);

        client.start();
        fake.flushMicrotasks();
        connector.authenticateCurrent();
        fake.flushMicrotasks();

        final inbound = RelayEnvelope(
          msgId: uuid,
          senderHash: hashB,
          recipientHash: hashA,
          ciphertext: [9, 8, 7],
          sentAtMs: 99,
          senderDeviceId: 'dev-2',
        );
        connector.last.pushServerFrame(RelayEnvelopeFrame(inbound));
        fake.flushMicrotasks();

        expect(received, hasLength(1));
        expect(received.single.ciphertext, [9, 8, 7]);
        // Auto-ack sent back (auth frame + ack).
        final frames = connector.last.sentFrames;
        expect(frames.whereType<RelayAckFrame>(), hasLength(1));
        expect((frames.whereType<RelayAckFrame>().single).msgId, uuid);

        client.dispose();
      });
    });

    test('sendEnvelope validates UUID v4 and blind-hash BEFORE the wire', () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        final client = RelayClient(
          accessToken: 'tok',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
        );
        client.start();
        fake.flushMicrotasks();
        connector.authenticateCurrent();
        fake.flushMicrotasks();

        // PII-shaped values are rejected at the boundary — they can never
        // become key material on the wire.
        expect(
          () => client.sendEnvelope(RelayEnvelope(
            msgId: '+919876543210',
            senderHash: hashA,
            recipientHash: hashB,
            ciphertext: [1],
            sentAtMs: 0,
            senderDeviceId: 'dev-1',
          )),
          throwsArgumentError,
        );
        expect(
          () => client.sendEnvelope(RelayEnvelope(
            msgId: uuid,
            senderHash: hashA,
            recipientHash: 'alice@example.com',
            ciphertext: [1],
            sentAtMs: 0,
            senderDeviceId: 'dev-1',
          )),
          throwsArgumentError,
        );
        expect(connector.last.sent, hasLength(1),
            reason: 'only the auth frame — nothing invalid hit the wire');

        // A valid envelope goes out (auth + envelope on the wire).
        client.sendEnvelope(envelope());
        fake.flushMicrotasks();
        expect(connector.last.sentFrames.whereType<RelayEnvelopeFrame>(),
            hasLength(1));
        final sent = connector.last.sentFrames
            .whereType<RelayEnvelopeFrame>()
            .single
            .envelope;
        expect(sent.senderHash, hashA);

        client.dispose();
      });
    });

    test('transient failure reconnects with backoff and re-authenticates', () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        final client = RelayClient(
          accessToken: 'tok',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
        );
        final phases = <RelayConnectionPhase>[];
        client.phases.listen(phases.add);

        client.start();
        fake.flushMicrotasks();
        connector.authenticateCurrent();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.connected);

        // Simulate the relay dying mid-session.
        connector.last.disconnect();
        fake.flushMicrotasks();

        expect(client.phase, RelayConnectionPhase.reconnecting);
        fake.elapse(const Duration(milliseconds: 10)); // backoff elapses
        fake.flushMicrotasks();
        expect(connector.sockets, hasLength(2),
            reason: 'a second socket was opened');
        expect(client.phase, RelayConnectionPhase.connecting);

        // The new session re-authenticates with the same token in the body.
        expect(connector.last.sent, hasLength(1));
        expect(
            (connector.last.lastFrame! as RelayAuthFrame).accessToken, 'tok');
        connector.authenticateCurrent();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.connected);

        client.dispose();
      });
    });

    test(
        'drop during the auth handshake is transient (reconnect, not terminal)',
        () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        final client = RelayClient(
          accessToken: 'tok',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
        );

        client.start();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.connecting);

        // The relay dies (or the network blips) BEFORE any auth_ack arrives.
        // No auth_ack:false was received, so this is NOT an auth rejection —
        // it must be retried with backoff, not classified terminal.
        connector.last.disconnect();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.reconnecting,
            reason: 'a pre-auth transport drop is a transient failure');
        expect(client.phase, isNot(RelayConnectionPhase.authFailed));

        fake.elapse(const Duration(milliseconds: 10)); // backoff elapses
        fake.flushMicrotasks();
        expect(connector.sockets, hasLength(2),
            reason: 'a second socket was opened after the pre-auth drop');
        expect(
            (connector.last.lastFrame! as RelayAuthFrame).accessToken, 'tok');
        connector.authenticateCurrent();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.connected);

        client.dispose();
      });
    });

    test('auth rejection close is terminal even though the socket then closes',
        () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        final client = RelayClient(
          accessToken: 'bad-token',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
        );
        final phases = <RelayConnectionPhase>[];
        client.phases.listen(phases.add);

        client.start();
        fake.flushMicrotasks();

        // The real relay sends auth_ack:false THEN closes with a policy
        // violation — the close must NOT turn the terminal rejection into a
        // reconnect.
        connector.authenticateCurrent(ok: false);
        fake.flushMicrotasks();
        connector.last.disconnect();
        fake.flushMicrotasks();

        expect(client.phase, RelayConnectionPhase.authFailed);
        fake.elapse(const Duration(minutes: 1));
        expect(connector.sockets, hasLength(1),
            reason: 'a rejected token is never retried');

        client.dispose();
      });
    });

    test('transport-heartbeat socket skips the app watchdog (no false stale)',
        () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        connector.transportHeartbeat = true;
        final client = RelayClient(
          accessToken: 'tok',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
          // A tiny stale window proves the watchdog is NOT running: even
          // with no frames for far longer, nothing tears the connection
          // down — the transport owns liveness.
          staleAfter: const Duration(seconds: 2),
          clock: fake.getClock(DateTime.fromMillisecondsSinceEpoch(0)).now,
        );

        client.start();
        fake.flushMicrotasks();
        connector.authenticateCurrent();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.connected);

        // Far longer than staleAfter with NO frames: the connection stays.
        fake.elapse(const Duration(minutes: 1));
        expect(client.phase, RelayConnectionPhase.connected,
            reason: 'transport heartbeat owns liveness — the app watchdog '
                'must not fire on idle');
        expect(connector.sockets, hasLength(1));
        expect(connector.last.closed, isFalse);

        // But when the TRANSPORT detects death (socket closes/fails), the
        // client still reconnects.
        connector.last.fail(StateError('pong timeout'));
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.reconnecting);

        client.dispose();
      });
    });

    test('connector failure is a transient failure (reconnect, no crash)', () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        final client = RelayClient(
          accessToken: 'tok',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
        );

        client.start();
        fake.flushMicrotasks();
        connector.authenticateCurrent();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.connected);

        connector.failNext = true; // the FIRST reconnect attempt will throw
        connector.last.disconnect();
        fake.flushMicrotasks();

        expect(client.phase, RelayConnectionPhase.reconnecting);
        // Backoff elapses → the retry runs; the connector fails. The client
        // must NOT crash, must NOT surface an unhandled error, and must NOT
        // treat the failure as an auth rejection (authFailed is terminal and
        // reserved for the relay's auth_ack:false verdict).
        fake.elapse(const Duration(milliseconds: 5));
        fake.flushMicrotasks();
        expect(connector.urls, hasLength(2),
            reason: 'a second connect attempt was made after the first '
                'failure — no crash');
        expect(client.phase, isNot(RelayConnectionPhase.authFailed));

        client.stop();
        client.dispose();
      });
    });

    test('stale heartbeat (no frames) tears down and reconnects', () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        // The injected clock is tied to fake_async's clock so "now" and the
        // timer schedule advance TOGETHER — no manual desync.
        final client = RelayClient(
          accessToken: 'tok',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
          // 30s window: the deliberate 40s silence trips the watchdog, but
          // the FRESH session is authenticated within 30s so it stays
          // healthy and never reconnects.
          staleAfter: const Duration(seconds: 30),
          clock: fake.getClock(DateTime.fromMillisecondsSinceEpoch(0)).now,
        );

        client.start();
        fake.flushMicrotasks();
        connector.authenticateCurrent();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.connected);

        // The relay's own ping frames keep the watchdog satisfied. Each
        // frame is flushed IMMEDIATELY so `notifyActivity` lands inside the
        // ping phase — if it were queued, it would arrive at the start of
        // the silence and reset the watchdog (masking the staleness).
        for (var i = 0; i < 6; i++) {
          fake.elapse(const Duration(seconds: 1));
          connector.last.pushServerFrame(RelayAckFrame('m$i'));
          fake.flushMicrotasks();
        }
        expect(client.phase, RelayConnectionPhase.connected,
            reason: 'regular traffic keeps the connection alive');

        // Silence → the watchdog closes the silent socket and the backoff
        // reopens a fresh one (the previous socket is gone — it was not kept
        // alive by any trickle of stale traffic).
        fake.elapse(const Duration(seconds: 40));
        fake.flushMicrotasks();
        expect(connector.sockets, hasLength(2),
            reason: 'a silent connection was replaced by the watchdog');
        expect(connector.sockets.first.closed, isTrue,
            reason: 'the silent socket was torn down');
        expect(client.phase, RelayConnectionPhase.connecting,
            reason: 'the fresh session is about to re-authenticate');

        // The fresh session authenticates and stays healthy — the relay's
        // own periodic ping frames (25s cadence, like the Go relay) keep its
        // watchdog satisfied, so no further reconnects fire.
        connector.authenticateCurrent();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.connected);
        for (var i = 0; i < 3; i++) {
          fake.elapse(const Duration(seconds: 20));
          connector.last.pushServerFrame(RelayAckFrame('ping-$i'));
          fake.flushMicrotasks();
        }
        expect(connector.sockets, hasLength(2),
            reason: 'a healthy authenticated session never reconnects');
        expect(client.phase, RelayConnectionPhase.connected);

        client.dispose();
      });
    });

    test('activity on the socket resets the staleness window', () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        final client = RelayClient(
          accessToken: 'tok',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
          staleAfter: const Duration(seconds: 5),
          clock: fake.getClock(DateTime.fromMillisecondsSinceEpoch(0)).now,
        );

        client.start();
        fake.flushMicrotasks();
        connector.authenticateCurrent();
        fake.flushMicrotasks();

        // Frame every 4s for a long time — never stale.
        for (var i = 0; i < 50; i++) {
          fake.elapse(const Duration(seconds: 4));
          connector.last.pushServerFrame(RelayAckFrame('m$i'));
        }
        expect(connector.sockets, hasLength(1));

        client.dispose();
      });
    });

    test('stop() cancels reconnection and disposes cleanly', () {
      fakeAsync((fake) {
        final connector = FakeRelaySocketConnector();
        final client = RelayClient(
          accessToken: 'tok',
          deviceId: 'dev-1',
          url: 'ws://relay',
          connector: connector,
          backoff: const _ImmediateBackoff(),
        );

        client.start();
        fake.flushMicrotasks();
        connector.authenticateCurrent();
        fake.flushMicrotasks();
        connector.last.disconnect();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.reconnecting);

        client.stop();
        fake.flushMicrotasks();
        expect(client.phase, RelayConnectionPhase.disconnected);

        // No reconnect fires after stop.
        fake.elapse(const Duration(minutes: 5));
        expect(connector.sockets, hasLength(1));

        client.dispose();
      });
    });

    test('dummy traffic generator emits UUID v4 keepalive ids on schedule', () {
      fakeAsync((fake) {
        final sentIds = <String>[];
        final generator = DummyTrafficGenerator(
          interval: const Duration(seconds: 15),
          blindHashId: hashA,
          deviceId: 'dev-1',
          send: sentIds.add,
        );
        generator.start();

        fake.elapse(const Duration(seconds: 15));
        expect(sentIds, hasLength(1));
        // Every id is a well-formed UUID v4 — never a sequence number or
        // anything that could fingerprint the device.
        expect(RelayEnvelope.isValidMsgId(sentIds.single), isTrue);

        fake.elapse(const Duration(seconds: 30));
        expect(sentIds, hasLength(3));

        generator.stop();
        fake.elapse(const Duration(minutes: 2));
        expect(sentIds, hasLength(3), reason: 'stop() halts emission');
      });
    });
  });
}
