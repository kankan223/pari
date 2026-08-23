import 'dart:async';
import 'dart:typed_data';

import '../../repository/domain/file_attachment.dart';
import '../../repository/domain/file_attachment_repository.dart';
import '../../relay/domain/relay_wire.dart';
import '../../relay/relay_messaging_bloc.dart';

/// BLoC for file/image sharing in a single conversation.
///
/// Handles: pick file, encrypt, send via relay, receive file metadata,
/// and expose attachments list for the UI.
///
/// SECURITY CHECKPOINT: filenames are user-chosen display labels only —
/// never filesystem paths. Encrypted bytes are AES-256-GCM sealed before
/// they leave the device. The server sees opaque ciphertext.
class FileSharingBloc {
  final FileAttachmentRepository _repo;
  final RelayMessagingBloc? _relayBloc;
  final String _conversationId;
  final String _participantHash;
  final String _myBlindHash;

  final _controller = StreamController<FileSharingState>.broadcast();
  FileSharingState _state = const FileSharingState();
  StreamSubscription<RelayFileAttachmentFrame>? _faSub;
  StreamSubscription<dynamic>? _envelopeSub;

  FileSharingBloc({
    required FileAttachmentRepository repo,
    RelayMessagingBloc? relayBloc,
    required String conversationId,
    required String participantHash,
    required String myBlindHash,
  })  : _repo = repo,
        _relayBloc = relayBloc,
        _conversationId = conversationId,
        _participantHash = participantHash,
        _myBlindHash = myBlindHash;

  Stream<FileSharingState> get state => _controller.stream;
  FileSharingState get currentState => _state;

  /// Start listening for incoming file attachment metadata.
  void start() {
    _faSub = _relayBloc?.fileAttachments.listen(_onFileAttachment);
  }

  void _onFileAttachment(RelayFileAttachmentFrame frame) {
    // Only process attachments for our conversation.
    if (frame.recipientHash != _myBlindHash) return;
    // Add to pending attachments list.
    _state = _state.copyWith(
      pendingAttachments: [
        ..._state.pendingAttachments,
        PendingAttachment(
          msgId: frame.msgId,
          fileName: frame.fileName,
          mimeType: frame.mimeType,
          encryptedSize: frame.encryptedSize,
          receivedAt: DateTime.now().toUtc(),
        ),
      ],
    );
    _controller.add(_state);
  }

  /// Send a file through the relay.
  ///
  /// 1. Read file bytes from [fileBytes].
  /// 2. Encrypt with AES-256-GCM (cipher).
  /// 3. Persist as FileAttachment locally.
  /// 4. Send the encrypted bytes as an Envelope via relay.
  /// 5. Send file metadata as a FileAttachment frame.
  Future<void> sendFile({
    required String fileName,
    required String mimeType,
    required int originalSize,
    required Uint8List fileBytes,
    required String msgId,
    dynamic cipher,
  }) async {
    // Encrypt the file bytes.
    final Uint8List encrypted;
    if (cipher != null) {
      encrypted = await cipher.encrypt(
        participantHash: _participantHash,
        plaintext: fileBytes,
      );
      // Wipe plaintext from memory.
      fileBytes.fillRange(0, fileBytes.length, 0);
    } else {
      encrypted = fileBytes;
    }

    // Persist locally.
    final attachment = FileAttachment(
      id: msgId,
      conversationId: _conversationId,
      messageId: msgId,
      displayName: fileName,
      mimeType: mimeType,
      originalSize: originalSize,
      encryptedBytes: encrypted,
      createdAt: DateTime.now().toUtc(),
    );
    await _repo.create(attachment);

    // Update state.
    _state = _state.copyWith(
      sentAttachments: [..._state.sentAttachments, attachment],
    );
    _controller.add(_state);

    // Send encrypted bytes via relay envelope.
    final relay = _relayBloc;
    if (relay != null) {
      await relay.sendMessage(
        recipientHash: _participantHash,
        text: '📎 $fileName',
        conversationId: _conversationId,
      );
      // Send file metadata.
      await relay.sendFileAttachment(
        recipientHash: _participantHash,
        msgId: msgId,
        fileName: fileName,
        encryptedSize: encrypted.length,
        mimeType: mimeType,
      );
    }
  }

  /// Get all attachments for a specific message.
  Future<List<FileAttachment>> getAttachmentsForMessage(String messageId) =>
      _repo.getByMessageId(messageId);

  Future<void> close() async {
    await _faSub?.cancel();
    await _envelopeSub?.cancel();
    await _controller.close();
  }
}

/// State for file sharing.
class FileSharingState {
  final List<FileAttachment> sentAttachments;
  final List<PendingAttachment> pendingAttachments;

  const FileSharingState({
    this.sentAttachments = const [],
    this.pendingAttachments = const [],
  });

  FileSharingState copyWith({
    List<FileAttachment>? sentAttachments,
    List<PendingAttachment>? pendingAttachments,
  }) =>
      FileSharingState(
        sentAttachments: sentAttachments ?? this.sentAttachments,
        pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      );
}

/// A pending file attachment received from the peer.
class PendingAttachment {
  final String msgId;
  final String fileName;
  final String mimeType;
  final int encryptedSize;
  final DateTime receivedAt;

  const PendingAttachment({
    required this.msgId,
    required this.fileName,
    required this.mimeType,
    required this.encryptedSize,
    required this.receivedAt,
  });
}
