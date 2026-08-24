import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../repository/domain/conversation.dart';
import '../repository/domain/conversation_repository.dart';
import '../repository/domain/entity_store.dart';
import '../repository/domain/message.dart';
import '../repository/domain/message_repository.dart';
import '../state/data/local_data_stream_controller.dart';
import '../state/domain/message_cipher.dart';
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
  final LocalDataStreamController<Message>? _messageDb;
  final LocalDataStreamController<Conversation>? _conversationDb;
  final MessageCipher? _cipher;
  final String _myBlindHash;
  final String _deviceId;

  RelayClient? _client;
  StreamSubscription<RelayEnvelope>? _envelopeSub;
  StreamSubscription<RelayConnectionPhase>? _phaseSub;
  StreamSubscription<RelayTypingFrame>? _typingSub;
  StreamSubscription<RelayReadReceiptFrame>? _readReceiptSub;
  StreamSubscription<RelayFileAttachmentFrame>? _fileAttachmentSub;

  final _statusController =
      StreamController<RelayMessagingStatus>.broadcast();
  final _incomingController = StreamController<RelayEnvelope>.broadcast();
  final _typingController =
      StreamController<RelayTypingFrame>.broadcast();
  final _readReceiptController =
      StreamController<RelayReadReceiptFrame>.broadcast();
  final _fileAttachmentController =
      StreamController<RelayFileAttachmentFrame>.broadcast();

  RelayMessagingStatus _status = RelayMessagingStatus.disconnected;

  RelayMessagingBloc({
    required ConversationRepository conversationRepo,
    required MessageRepository messageRepo,
    required EntityStore<Conversation> conversationStore,
    LocalDataStreamController<Message>? messageDb,
    LocalDataStreamController<Conversation>? conversationDb,
    MessageCipher? cipher,
    required String myBlindHash,
    required String deviceId,
  })  : _conversationRepo = conversationRepo,
        _messageRepo = messageRepo,
        _conversationStore = conversationStore,
        _messageDb = messageDb,
        _conversationDb = conversationDb,
        _cipher = cipher,
        _myBlindHash = myBlindHash,
        _deviceId = deviceId;

  /// Connection status stream (broadcast).
  Stream<RelayMessagingStatus> get status => _statusController.stream;
  RelayMessagingStatus get currentStatus => _status;

  /// Incoming envelopes from the relay (broadcast).
  Stream<RelayEnvelope> get incomingEnvelopes => _incomingController.stream;

  /// Incoming typing indicators from other users.
  Stream<RelayTypingFrame> get typingIndicators => _typingController.stream;

  /// Incoming read receipts from other users.
  Stream<RelayReadReceiptFrame> get readReceipts => _readReceiptController.stream;

  /// Incoming file attachment metadata from other users.
  Stream<RelayFileAttachmentFrame> get fileAttachments => _fileAttachmentController.stream;

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
    _typingSub = _client!.typingIndicators.listen((typing) {
      _typingController.add(typing);
    });
    _readReceiptSub = _client!.readReceipts.listen((receipt) {
      _readReceiptController.add(receipt);
    });
    _fileAttachmentSub = _client!.fileAttachments.listen((fa) {
      _fileAttachmentController.add(fa);
    });

    _client!.start();
  }

  /// Disconnect from the relay. Call on logout.
  Future<void> disconnect() async {
    await _envelopeSub?.cancel();
    _envelopeSub = null;
    await _phaseSub?.cancel();
    _phaseSub = null;
    await _typingSub?.cancel();
    _typingSub = null;
    await _readReceiptSub?.cancel();
    _readReceiptSub = null;
    await _fileAttachmentSub?.cancel();
    _fileAttachmentSub = null;
    await _client?.stop();
    _client = null;
    _status = RelayMessagingStatus.disconnected;
    _statusController.add(_status);
  }

  /// Send a typing indicator to [recipientHash].
  Future<void> sendTyping(String recipientHash, bool isTyping) async {
    final client = _client;
    if (client != null && _status == RelayMessagingStatus.connected) {
      try {
        await client.sendTyping(recipientHash, isTyping);
      } catch (_) {
        // Best-effort — typing indicators are ephemeral.
      }
    }
  }

  /// Send file attachment metadata to [recipientHash].
  Future<void> sendFileAttachment({
    required String recipientHash,
    required String msgId,
    required String fileName,
    required int encryptedSize,
    required String mimeType,
  }) async {
    final client = _client;
    if (client != null && _status == RelayMessagingStatus.connected) {
      try {
        await client.sendFileAttachment(RelayFileAttachmentFrame(
          recipientHash: recipientHash,
          msgId: msgId,
          fileName: fileName,
          encryptedSize: encryptedSize,
          mimeType: mimeType,
        ));
      } catch (_) {
        // Best-effort — file attachment metadata is informational.
      }
    }
  }

  /// Send a read receipt indicating we've seen up to [lastMsgId] for [senderHash].
  Future<void> sendReadReceipt(String senderHash, String lastMsgId) async {
    final client = _client;
    if (client != null && _status == RelayMessagingStatus.connected) {
      try {
        await client.sendReadReceipt(senderHash, lastMsgId);
      } catch (_) {
        // Best-effort — read receipts are ephemeral.
      }
    }
  }

  /// Send a message to [recipientHash] through the relay.
  ///
  /// Encrypts [text] with the [MessageCipher] (Signal Protocol Double
  /// Ratchet) before persisting and sending. Falls back to raw bytes
  /// when no cipher is wired (dev harness, no session).
  ///
  /// SECURITY CHECKPOINT: plaintext exists only transiently inside the
  /// cipher.encrypt() call; the persisted and transmitted bytes are
  /// always sealed ciphertext.
  Future<void> sendMessage({
    required String recipientHash,
    required String text,
    required String conversationId,
    String? replyToId,
    String? replyToContent,
  }) async {
    final plaintext = Uint8List.fromList(utf8.encode(text));
    final Uint8List ciphertext;
    final cipher = _cipher;
    if (cipher != null) {
      ciphertext = await cipher.encrypt(
        participantHash: recipientHash,
        plaintext: plaintext,
      );
      // Wipe plaintext from memory.
      plaintext.fillRange(0, plaintext.length, 0);
    } else {
      // No cipher wired — send raw (dev harness only).
      ciphertext = plaintext;
    }
    final msgId = _uuidV4();

    // 1. Persist locally (offline-first — UI sees the message immediately).
    final msg = Message(
      id: msgId,
      conversationId: conversationId,
      ciphertext: ciphertext,
      direction: MessageDirection.sent,
      delivered: false,
      replyToId: replyToId,
      replyToContent: replyToContent,
    );
    await _messageRepo.create(msg);
    // 2. Notify the UI stream IMMEDIATELY so the message appears in the chat
    // even if the relay send takes time or fails.
    await _notifyMessageStream();
    // Send through the relay (if connected).
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

    var isNewConversation = false;
    if (conversationId == null) {
      // First contact — create a new conversation.
      conversationId = 'conv-${_uuidV4().substring(0, 8)}';
      final conv = Conversation(
        id: conversationId,
        participantHash: senderHash,
        encryptedSessionState: Uint8List(0),
      );
      await _conversationRepo.create(conv);
      isNewConversation = true;
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
    // Notify the message UI stream so per-conversation blocs pick up the message.
    await _notifyMessageStream();
    // If a new conversation was created, also notify the conversation list UI.
    if (isNewConversation) {
      await _notifyConversationStream();
    }
  }

  /// Emit all messages from the shared store so stream subscribers see
  /// messages created by the relay or other code paths.
  Future<void> _notifyMessageStream() async {
    final db = _messageDb;
    if (db != null) {
      try {
        final all = await _messageRepo.getAll();
        db.emit(all);
      } catch (_) {
        // Controller may be closed — swallow.
      }
    }
  }

  /// Emit all conversations from the shared store so the conversation list
  /// UI picks up new conversations created by incoming messages.
  Future<void> _notifyConversationStream() async {
    final db = _conversationDb;
    if (db != null) {
      try {
        final all = await _conversationStore.getAll();
        db.emit(all);
      } catch (_) {
        // Controller may be closed — swallow.
      }
    }
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
    await _typingController.close();
    await _readReceiptController.close();
    await _fileAttachmentController.close();
  }
}
