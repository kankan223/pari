import 'dart:convert';

import 'package:civic_commons/relay/domain/relay_wire.dart';
import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 6.4): the wire codec must (a) emit EXACTLY the
/// protojson snake_case contract the Go relay produces (UseProtoNames), (b)
/// round-trip opaque base64 ciphertext byte-for-byte, and (c) reject
/// PII-shaped or malformed values — a phone number, username, or email can
/// never be serialized into a key-bearing field.
void main() {
  group('RelayEnvelope wire contract (mirrors civic.relay.v1.Envelope)', () {
    test('serializes to protojson snake_case with base64 ciphertext', () {
      final envelope = RelayEnvelope(
        msgId: '4f4a9e10-0b6e-4f9e-9a4c-2e6c7e1a8f0d',
        senderHash: 'a' * 64,
        recipientHash: 'b' * 64,
        ciphertext: [1, 2, 3, 250, 251, 252],
        sentAtMs: 1700000000123,
        senderDeviceId: 'dev-1',
      );

      final json = envelope.toJson();

      // protojson UseProtoNames: snake_case keys.
      expect(
          json.keys,
          containsAll([
            'msg_id',
            'sender_hash',
            'recipient_hash',
            'ciphertext',
            'sent_at_ms',
            'sender_device_id'
          ]));
      expect(json['msg_id'], '4f4a9e10-0b6e-4f9e-9a4c-2e6c7e1a8f0d');
      expect(json['ciphertext'], base64Encode([1, 2, 3, 250, 251, 252]));
      expect(json['sent_at_ms'], 1700000000123);
    });

    test('round-trips opaque ciphertext byte-for-byte', () {
      final original = List<int>.generate(128, (i) => i * 7 % 256);
      final envelope = RelayEnvelope(
        msgId: '4f4a9e10-0b6e-4f9e-9a4c-2e6c7e1a8f0d',
        senderHash: 'a' * 64,
        recipientHash: 'b' * 64,
        ciphertext: original,
        sentAtMs: 0,
        senderDeviceId: 'dev-1',
      );

      final frame = RelayEnvelopeFrame(envelope);
      final restored = RelayEnvelope.fromJson(frame.payload());

      expect(restored, isNotNull);
      expect(restored!.ciphertext, original);
      expect(restored.msgId, envelope.msgId);
      expect(restored.senderHash, envelope.senderHash);
      expect(restored.recipientHash, envelope.recipientHash);
    });

    test('fromJson drops malformed envelopes instead of throwing', () {
      expect(RelayEnvelope.fromJson({'msg_id': 'x'}), isNull);
      expect(
        RelayEnvelope.fromJson({
          'msg_id': '4f4a9e10-0b6e-4f9e-9a4c-2e6c7e1a8f0d',
          'sender_hash': 'a' * 64,
          'recipient_hash': 'b' * 64,
          'ciphertext': '!!!not-base64!!!',
          'sender_device_id': 'd',
        }),
        isNull,
      );
    });

    test('isValidMsgId accepts UUID v4 and rejects PII-shaped values', () {
      expect(
        RelayEnvelope.isValidMsgId('4f4a9e10-0b6e-4f9e-9a4c-2e6c7e1a8f0d'),
        isTrue,
      );
      expect(RelayEnvelope.isValidMsgId('not-a-uuid'), isFalse);
      expect(RelayEnvelope.isValidMsgId('+919876543210'), isFalse);
      expect(RelayEnvelope.isValidMsgId('user@example.com'), isFalse);
      // Version nibble must be 4, variant must be 8/9/a/b.
      expect(
        RelayEnvelope.isValidMsgId('4f4a9e10-0b6e-5f9e-9a4c-2e6c7e1a8f0d'),
        isFalse,
      );
    });

    test('isValidBlindHash requires exactly 64 lowercase hex', () {
      expect(RelayEnvelope.isValidBlindHash('a' * 64), isTrue);
      expect(RelayEnvelope.isValidBlindHash('A' * 64), isFalse); // uppercase
      expect(RelayEnvelope.isValidBlindHash('a' * 63), isFalse);
      expect(RelayEnvelope.isValidBlindHash('+919876543210'), isFalse);
      expect(RelayEnvelope.isValidBlindHash('alice'), isFalse);
    });
  });

  group('RelayFrame encode/decode (oneof payload)', () {
    test('auth frame encodes as {"auth":{...}} with token in the BODY', () {
      const frame = RelayAuthFrame(
        accessToken: 'jwt.payload.signature',
        deviceId: 'dev-9',
      );

      final wire = frame.encode();
      expect(
          wire,
          '{"auth":{"access_token":"jwt.payload.signature",'
          '"device_id":"dev-9"}}');

      final decoded = RelayFrame.decode(wire);
      expect(decoded, isA<RelayAuthFrame>());
      final auth = decoded! as RelayAuthFrame;
      expect(auth.accessToken, 'jwt.payload.signature');
      expect(auth.deviceId, 'dev-9');
    });

    test('auth_ack round-trips authenticated + blind_hash_id', () {
      final frame = RelayAuthAckFrame(
        authenticated: true,
        blindHashId: 'c' * 64,
      );
      final decoded = RelayFrame.decode(frame.encode());
      expect(decoded, isA<RelayAuthAckFrame>());
      expect((decoded! as RelayAuthAckFrame).authenticated, isTrue);
      expect((decoded as RelayAuthAckFrame).blindHashId, 'c' * 64);
    });

    test('envelope frame round-trips through the wire text', () {
      final envelope = RelayEnvelope(
        msgId: '4f4a9e10-0b6e-4f9e-9a4c-2e6c7e1a8f0d',
        senderHash: 'a' * 64,
        recipientHash: 'b' * 64,
        ciphertext: [42, 43, 44],
        sentAtMs: 123,
        senderDeviceId: 'dev-1',
      );
      final decoded = RelayFrame.decode(RelayEnvelopeFrame(envelope).encode());
      expect(decoded, isA<RelayEnvelopeFrame>());
      final restored = (decoded! as RelayEnvelopeFrame).envelope;
      expect(restored.ciphertext, [42, 43, 44]);
      expect(restored.msgId, envelope.msgId);
    });

    test('ack frame round-trips msg_id', () {
      final decoded = RelayFrame.decode(const RelayAckFrame('m1').encode());
      expect(decoded, isA<RelayAckFrame>());
      expect((decoded! as RelayAckFrame).msgId, 'm1');
    });

    test('error frame round-trips code + message', () {
      const frame =
          RelayErrorFrame(code: 'policy_violation', message: 'auth required');
      expect(frame.encode(),
          '{"error":{"code":"policy_violation","message":"auth required"}}');

      final decoded = RelayFrame.decode(frame.encode());
      expect(decoded, isA<RelayErrorFrame>());

      expect((decoded! as RelayErrorFrame).code, 'policy_violation');
      expect((decoded as RelayErrorFrame).message, 'auth required');
    });

    test('server envelope frame parses the EXACT Go protojson shape', () {
      // A frame as the Go relay emits it (protojson, UseProtoNames,
      // base64 bytes).
      const wire =
          '{"envelope":{"msg_id":"4f4a9e10-0b6e-4f9e-9a4c-2e6c7e1a8f0d",'
          '"sender_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",'
          '"recipient_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",'
          '"ciphertext":"AQID","sent_at_ms":1700000000123,'
          '"sender_device_id":"dev-7"}}';

      final frame = RelayFrame.decode(wire);
      expect(frame, isA<RelayEnvelopeFrame>());
      final env = (frame! as RelayEnvelopeFrame).envelope;
      expect(env.ciphertext, [1, 2, 3]);
      expect(env.sentAtMs, 1700000000123);
      expect(env.senderDeviceId, 'dev-7');
    });

    test(
        'unknown oneof members and malformed JSON are dropped (DiscardUnknown)',
        () {
      expect(RelayFrame.decode('{"future_frame":{"x":1}}'), isNull);
      expect(RelayFrame.decode('not json'), isNull);
      expect(RelayFrame.decode('{"auth":42}'), isNull);
      expect(RelayFrame.decode('{}'), isNull);
    });
  });
}
