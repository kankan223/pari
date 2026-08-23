import 'dart:convert';

/// Ciphertext envelope routed by the relay (Task 6.4).
///
/// Mirrors `civic.relay.v1.Envelope` in `services/proto/relay.proto`
/// (Task 4.4). The relay is a BYTE ROUTER: [ciphertext] is opaque — the
/// client produces it with the Signal session layer (Task 6.3) and the
/// server forwards it without ever inspecting it.
///
/// SECURITY CONTRACT: sender/recipient are 64-hex blind hash IDs, NEVER
/// phone numbers or usernames; [ciphertext] is the sealed payload, NEVER
/// plaintext. The wire format is protojson (snake_case keys, base64 bytes)
/// exactly as the Go relay's `protojson.MarshalOptions{UseProtoNames: true}`
/// emits — see `services/internal/relay/framing.go`.
class RelayEnvelope {
  /// Client-generated UUID v4 message id (used for delivery acks and the
  /// server-side idempotency key).
  final String msgId;

  /// Authenticated sender blind hash (server-validated — client-supplied
  /// values are always overridden by the relay).
  final String senderHash;

  /// Target recipient blind hash.
  final String recipientHash;

  /// Opaque E2EE ciphertext. Never inspected, decrypted, or logged.
  final List<int> ciphertext;

  /// Client clock when the message was composed (ms since epoch). Zero is
  /// server-defaulted to now.
  final int sentAtMs;

  /// The sending device's public-key id (multi-device fan-out scoping).
  final String senderDeviceId;

  const RelayEnvelope({
    required this.msgId,
    required this.senderHash,
    required this.recipientHash,
    required this.ciphertext,
    required this.sentAtMs,
    required this.senderDeviceId,
  });

  /// Encodes this envelope into the protojson wire map.
  Map<String, Object?> toJson() => {
        'msg_id': msgId,
        'sender_hash': senderHash,
        'recipient_hash': recipientHash,
        'ciphertext': base64Encode(ciphertext),
        'sent_at_ms': sentAtMs,
        'sender_device_id': senderDeviceId,
      };

  /// Decodes an envelope from a protojson wire map (server→client).
  ///
  /// Returns null when required fields are missing or malformed — a
  /// malformed envelope is DROPPED, never thrown (the connection must
  /// survive bad peers).
  static RelayEnvelope? fromJson(Map<String, Object?> json) {
    final msgId = json['msg_id'];
    final senderHash = json['sender_hash'];
    final recipientHash = json['recipient_hash'];
    final ciphertext = json['ciphertext'];
    final senderDeviceId = json['sender_device_id'];
    final sentAtMs = json['sent_at_ms'];
    if (msgId is! String ||
        msgId.isEmpty ||
        senderHash is! String ||
        recipientHash is! String ||
        ciphertext is! String ||
        senderDeviceId is! String) {
      return null;
    }
    List<int> bytes;
    try {
      bytes = base64Decode(ciphertext);
    } on FormatException {
      return null;
    }
    return RelayEnvelope(
      msgId: msgId,
      senderHash: senderHash,
      recipientHash: recipientHash,
      ciphertext: bytes,
      sentAtMs: sentAtMs is int ? sentAtMs : 0,
      senderDeviceId: senderDeviceId,
    );
  }

  /// Strict UUID v4 validation for client-generated message ids.
  ///
  /// SECURITY CHECKPOINT: the idempotency-key registry (Task 5.3) keys on
  /// `msg_id`; only a well-formed UUID v4 may enter a Redis key. This
  /// validator rejects anything else — PII-shaped payloads can never become
  /// key material.
  static bool isValidMsgId(String value) => _uuidV4RegExp.hasMatch(value);

  static final RegExp _uuidV4RegExp = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-'
    r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  /// Validates a blind hash id: exactly 64 lowercase hex characters.
  ///
  /// SECURITY CHECKPOINT: the ONLY identity the relay transports. Any value
  /// that is not a 64-hex hash is rejected at the port boundary.
  static bool isValidBlindHash(String value) =>
      _blindHashRegExp.hasMatch(value);

  static final RegExp _blindHashRegExp = RegExp(r'^[0-9a-f]{64}$');
}

/// The oneof payload tag of a relay frame (protojson member name).
enum RelayFrameType {
  /// Client → server, FIRST frame: carries the access token (never the URL).
  auth('auth'),

  /// Server → client: authentication result.
  authAck('auth_ack'),

  /// Bidirectional: a routed envelope.
  envelope('envelope'),

  /// Bidirectional: delivery acknowledgement.
  ack('ack'),

  /// Server → client: relay error.
  error('error'),

  /// Bidirectional: typing indicator.
  typing('typing'),

  /// Bidirectional: read receipt.
  readReceipt('read_receipt');

  const RelayFrameType(this.wireName);

  /// The protojson member name (`UseProtoNames`).
  final String wireName;

  static RelayFrameType? fromWireName(String name) {
    for (final t in values) {
      if (t.wireName == name) {
        return t;
      }
    }
    return null;
  }
}

/// A relay wire frame (oneof payload), mirroring `civic.relay.v1.ClientFrame`
/// / `ServerFrame`. Frames serialize to protojson text frames.
sealed class RelayFrame {
  const RelayFrame();

  /// The oneof member name that identifies this frame on the wire.
  RelayFrameType get type;

  /// The payload keyed by the member name — the frame body.
  Map<String, Object?> payload();

  /// Encodes this frame as the full wire JSON text.
  String encode() {
    final body = payload();
    return jsonEncode(<String, Object?>{type.wireName: body});
  }

  /// Decodes a wire JSON text into a [RelayFrame], or null when the text is
  /// not a frame the client understands (unknown oneof members are dropped
  /// — forward compatibility with newer server deployments, mirroring the
  /// relay's `DiscardUnknown`).
  static RelayFrame? decode(String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    if (decoded.length != 1) {
      return null;
    }
    final entry = decoded.entries.first;
    final type = RelayFrameType.fromWireName(entry.key);
    final body = entry.value;
    if (type == null || body is! Map<String, Object?>) {
      return null;
    }
    switch (type) {
      case RelayFrameType.auth:
        return RelayAuthFrame.fromJson(body);
      case RelayFrameType.authAck:
        return RelayAuthAckFrame.fromJson(body);
      case RelayFrameType.envelope:
        return RelayEnvelopeFrame.fromJson(body);
      case RelayFrameType.ack:
        return RelayAckFrame.fromJson(body);
      case RelayFrameType.error:
        return RelayErrorFrame.fromJson(body);
      case RelayFrameType.typing:
        return RelayTypingFrame.fromJson(body);
      case RelayFrameType.readReceipt:
        return RelayReadReceiptFrame.fromJson(body);
    }
  }
}

/// `auth` — the first client frame (access token + device id in the BODY,
/// never the URL).
class RelayAuthFrame extends RelayFrame {
  final String accessToken;
  final String deviceId;

  const RelayAuthFrame({required this.accessToken, required this.deviceId});

  @override
  RelayFrameType get type => RelayFrameType.auth;

  @override
  Map<String, Object?> payload() => {
        'access_token': accessToken,
        'device_id': deviceId,
      };

  static RelayAuthFrame? fromJson(Map<String, Object?> json) {
    final token = json['access_token'];
    final deviceId = json['device_id'];
    if (token is! String || deviceId is! String) {
      return null;
    }
    return RelayAuthFrame(accessToken: token, deviceId: deviceId);
  }
}

/// `auth_ack` — the server's authentication verdict.
class RelayAuthAckFrame extends RelayFrame {
  final bool authenticated;
  final String? blindHashId;

  const RelayAuthAckFrame({required this.authenticated, this.blindHashId});

  @override
  RelayFrameType get type => RelayFrameType.authAck;

  @override
  Map<String, Object?> payload() => {
        'authenticated': authenticated,
        if (blindHashId != null) 'blind_hash_id': blindHashId,
      };

  static RelayAuthAckFrame? fromJson(Map<String, Object?> json) {
    final ok = json['authenticated'];
    final hash = json['blind_hash_id'];
    if (ok is! bool) {
      return null;
    }
    return RelayAuthAckFrame(
      authenticated: ok,
      blindHashId: hash is String ? hash : null,
    );
  }
}

/// `envelope` — a routed ciphertext envelope.
class RelayEnvelopeFrame extends RelayFrame {
  final RelayEnvelope envelope;

  const RelayEnvelopeFrame(this.envelope);

  @override
  RelayFrameType get type => RelayFrameType.envelope;

  @override
  Map<String, Object?> payload() => envelope.toJson();

  static RelayEnvelopeFrame? fromJson(Map<String, Object?> json) {
    final envelope = RelayEnvelope.fromJson(json);
    return envelope == null ? null : RelayEnvelopeFrame(envelope);
  }
}

/// `ack` — delivery acknowledgement (enables offline-queue purge).
class RelayAckFrame extends RelayFrame {
  final String msgId;

  const RelayAckFrame(this.msgId);

  @override
  RelayFrameType get type => RelayFrameType.ack;

  @override
  Map<String, Object?> payload() => {'msg_id': msgId};

  static RelayAckFrame? fromJson(Map<String, Object?> json) {
    final msgId = json['msg_id'];
    if (msgId is! String || msgId.isEmpty) {
      return null;
    }
    return RelayAckFrame(msgId);
  }
}

/// `error` — a relay error (connection stays up unless terminal).
class RelayErrorFrame extends RelayFrame {
  final String code;
  final String message;

  const RelayErrorFrame({required this.code, required this.message});

  @override
  RelayFrameType get type => RelayFrameType.error;

  @override
  Map<String, Object?> payload() => {'code': code, 'message': message};

  static RelayErrorFrame? fromJson(Map<String, Object?> json) {
    final code = json['code'];
    final message = json['message'];
    if (code is! String || message is! String) {
      return null;
    }
    return RelayErrorFrame(code: code, message: message);
  }
}

/// `typing` — ephemeral typing indicator (never queued offline).
class RelayTypingFrame extends RelayFrame {
  final String recipientHash;
  final bool isTyping;

  const RelayTypingFrame({required this.recipientHash, required this.isTyping});

  @override
  RelayFrameType get type => RelayFrameType.typing;

  @override
  Map<String, Object?> payload() => {
        'recipient_hash': recipientHash,
        'is_typing': isTyping,
      };

  static RelayTypingFrame? fromJson(Map<String, Object?> json) {
    final recipientHash = json['recipient_hash'];
    final isTyping = json['is_typing'];
    if (recipientHash is! String || isTyping is! bool) {
      return null;
    }
    return RelayTypingFrame(recipientHash: recipientHash, isTyping: isTyping);
  }
}

/// `read_receipt` — ephemeral read receipt (never queued offline).
class RelayReadReceiptFrame extends RelayFrame {
  final String senderHash;
  final String lastMsgId;

  const RelayReadReceiptFrame({required this.senderHash, required this.lastMsgId});

  @override
  RelayFrameType get type => RelayFrameType.readReceipt;

  @override
  Map<String, Object?> payload() => {
        'sender_hash': senderHash,
        'last_msg_id': lastMsgId,
      };

  static RelayReadReceiptFrame? fromJson(Map<String, Object?> json) {
    final senderHash = json['sender_hash'];
    final lastMsgId = json['last_msg_id'];
    if (senderHash is! String || lastMsgId is! String) {
      return null;
    }
    return RelayReadReceiptFrame(senderHash: senderHash, lastMsgId: lastMsgId);
  }
}
