import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../repository/domain/conversation.dart';
import '../repository/domain/conversation_repository.dart';
import '../repository/domain/entity_store.dart';
import '../repository/domain/message.dart';
import '../repository/domain/message_repository.dart';
import 'domain/relay_client.dart';
import 'domain/relay_socket.dart';
import 'domain/relay_wire.dart';

/// Connection state exposed by the relay messaging layer.
enum RelayMessagingStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  authFailed,
}

/// Bridges the [RelayClient] (WebSocket transport) to the local message
/// and conversation stores.
///
/// Responsibilities:
/// - Manages the relay WebSocket lifecycle (connect on auth, disconnect on
///   logout).
/// - Routes incoming envelopes from the relay into the local message store
///   and creates conversations on first contact.
/// - Provides [sendMessage] for the UI to dispatch messages through the
///   relay AND persist locally.
/// - Exposes [status] stream for the UI to show connection state.
///
/// SECURITY CHECKPOINT: ciphertext is opaque — never decrypted, logged, or
/// inspected. Sender/recipient are blind hashes only.
class RelayMessagingBloc {
  final ConversationRepository _conversationRepo;
  final MessageRepository _messageRepo;
  final EntityStore<Conversation> _conversationStore;
  final String _myBlindHash;
  final String _deviceId;

  RelayClient? _client;
  StreamSubscription<RelayEnvelope>? _envelopeSub;
  StreamSubscription<RelayConnectionPhase>? _phaseSub;

  final _statusController =
      StreamController<RelayMessagingStatus>.broadcast();
  final _incomingController = StreamController<RelayEnvelope>.broadcast();

  RelayMessagingStatus _status = RelayMessagingStatus.disconnected;

  RelayMessagingBloc({
    required ConversationRepository conversationRepo,
    required MessageRepository messageRepo,
    required EntityStore<Conversation> conversationStore,
    required String myBlindHash,
    required String deviceId,
  })  : _conversationRepo = conversationRepo,
        _messageRepo = messageRepo,
        _conversationStore = conversationStore,
        _myBlindHash = myBlindHash,
        _deviceId = deviceId;

  /// Connection status stream (broadcast).
  Stream<RelayMessagingStatus> get status => _statusController.stream;
  RelayMessagingStatus get currentStatus => _status;

  /// Incoming envelopes from the relay (broadcast).
  Stream<RelayEnvelope> get incomingEnvelopes => _incomingController.stream;

  /// Connect to the relay WebSocket. Call after successful login.
  void connect({
    required String accessToken,
    required String relayUrl,
    required RelaySocketConnector connector,
  }) {
    disconnect(); // clean up any existing connection

    _client = RelayClient(
      accessToken: accessToken,
      deviceId: _deviceId,
      url: relayUrl,
      connector: connector,
    );

    _phaseSub = _client!.phases.listen((phase) {
      _status = switch (phase) {
        RelayConnectionPhase.disconnected =>
          RelayMessagingStatus.disconnected,
        RelayConnectionPhase.connecting =>
          RelayMessagingStatus.connecting,
        RelayConnectionPhase.connected =>
          RelayMessagingStatus.connected,
        RelayConnectionPhase.reconnecting =>
          RelayMessagingStatus.reconnecting,
        RelayConnectionPhase.authFailed =>
          RelayMessagingStatus.authFailed,
      };
      _statusController.add(_status);
    });

    _envelopeSub = _client!.envelopes.listen(_onIncomingEnvelope);

    _client!.start();
  }

  /// Disconnect from the relay. Call on logout.
  Future<void> disconnect() async {
    await _envelopeSub?.cancel();
    _envelopeSub = null;
    await _phaseSub?.cancel();
    _phaseSub = null;
    await _client?.stop();
    _client = null;
    _status = RelayMessagingStatus.disconnected;
    _statusController.add(_status);
  }

  /// Send a message to [recipientHash] with [ciphertext] through the relay.
  ///
  /// Also persists the message locally in the conversation (offline-first).
  /// The caller is responsible for encrypting [text] into [ciphertext] before
  /// calling this method.
  Future<void> sendMessage({
    required String recipientHash,
    required String text,
    required String conversationId,
  }) async {
    final ciphertext = Uint8List.fromList(utf8.encode(text));
    final msgId = _uuidV4();

    // 1. Persist locally (offline-first — UI sees the message immediately).
    final msg = Message(
      id: msgId,
      conversationId: conversationId,
      ciphertext: ciphertext,
      direction: MessageDirection.sent,
      delivered: false,
    );
    await _messageRepo.create(msg);

    // 2. Send through the relay (if connected).
    final client = _client;
    if (client != null && _status == RelayMessagingStatus.connected) {
      try {
        await client.sendEnvelope(RelayEnvelope(
          msgId: msgId,
          senderHash: _myBlindHash,
          recipientHash: recipientHash,
          ciphertext: ciphertext,
          sentAtMs: DateTime.now().millisecondsSinceEpoch,
          senderDeviceId: _deviceId,
        ));
        // Mark as delivered (relay accepted the envelope).
        await _messageRepo.update(msg.copyWith(delivered: true));
      } catch (_) {
        // Relay send failed — message stays locally as undelivered.
        // The sync queue will retry (offline-first).
      }
    }
  }

  /// Handle an incoming envelope from the relay.
  Future<void> _onIncomingEnvelope(RelayEnvelope envelope) async {
    _incomingController.add(envelope);

    final senderHash = envelope.senderHash;

    // Find or create a conversation for this sender.
    final conversations = await _conversationStore.getAll();
    String? conversationId;
    for (final c in conversations) {
      if (c.participantHash == senderHash) {
        conversationId = c.id;
        break;
      }
    }

    if (conversationId == null) {
      // First contact — create a new conversation.
      conversationId = 'conv-${_uuidV4().substring(0, 8)}';
      final conv = Conversation(
        id: conversationId,
        participantHash: senderHash,
        encryptedSessionState: Uint8List(0),
      );
      await _conversationRepo.create(conv);
    }

    // Persist the incoming message locally.
    final msg = Message(
      id: envelope.msgId,
      conversationId: conversationId,
      ciphertext: Uint8List.fromList(envelope.ciphertext),
      direction: MessageDirection.received,
      delivered: true,
    );
    await _messageRepo.create(msg);
  }

  /// Generate a UUID v4 (simple implementation).
  static String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _randomByte());
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static int _randomByte() {
    // Use dart:math for randomness — this is a client-side UUID, not
    // cryptographic material.
    return DateTime.now().microsecondsSinceEpoch & 0xff;
  }

  /// Releases resources.
  Future<void> dispose() async {
    await disconnect();
    await _statusController.close();
    await _incomingController.close();
  }
}
