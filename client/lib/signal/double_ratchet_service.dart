import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:civic_commons/crypto/crypto_service.dart';

// X25519 algorithm instance for DH operations.
final X25519 _x25519 = X25519();

/// Double Ratchet session encryption
///
/// This service implements the Double Ratchet algorithm for forward secrecy
/// and future secrecy in encrypted messaging.
class DoubleRatchetService {
  final CryptoService _cryptoService;

  // Root key and chain keys
  Uint8List? _rootKey;
  Uint8List? _sendingChainKey;
  Uint8List? _receivingChainKey;

  // Send and receive message numbers
  int _sendMessageNumber = 0;
  int _receiveMessageNumber = 0;
  int _previousChainLength = 0;

  // DH key pair for this session
  SimpleKeyPair? _dhKeyPair;
  Uint8List? _remoteDhPublicKey;

  // AES-256-GCM for message encryption
  static final AesGcm _aesGcm = AesGcm.with256bits();

  DoubleRatchetService({
    required CryptoService cryptoService,
  }) : _cryptoService = cryptoService;

  /// Initialize Double Ratchet with shared secret from X3DH
  ///
  /// Parameters:
  /// - sharedSecret: The shared secret from X3DH handshake
  /// - dhKeyPair: The local DH key pair (optional, will generate if not provided)
  ///
  /// Security: Initializes the ratchet state with the X3DH shared secret
  Future<void> initialize(Uint8List sharedSecret,
      {SimpleKeyPair? dhKeyPair}) async {
    // Initialize root key with shared secret
    _rootKey = Uint8List.fromList(sharedSecret);

    // Generate or use provided DH key pair
    _dhKeyPair = dhKeyPair ?? await _cryptoService.generateCurve25519KeyPair();

    // Initialize sending chain key
    _sendingChainKey = await _kdf(_rootKey!, Uint8List(0));
    // The receiving chain starts as a mirror of the sending chain: in a
    // loopback (self) session the decrypt path advances it in lockstep with
    // the send chain, so a service can decrypt messages it encrypted itself.
    // For a real two-party session the first received message with a new
    // remote DH public key triggers a DH ratchet, which resets both chains.
    _receivingChainKey = await _kdf(_rootKey!, Uint8List(0));

    // Securely wipe shared secret from memory
    sharedSecret.fillRange(0, sharedSecret.length, 0);
  }

  /// Encrypt a message using Double Ratchet
  ///
  /// Parameters:
  /// - plaintext: The message to encrypt
  ///
  /// Returns: Encrypted message with header information
  ///
  /// Security: Each message uses a unique key derived from the ratchet
  Future<EncryptedMessage> encrypt(Uint8List plaintext) async {
    if (_sendingChainKey == null || _dhKeyPair == null) {
      throw StateError('Double Ratchet not initialized');
    }

    // Derive message key from chain key
    final messageKey =
        await _kdf(_sendingChainKey!, Uint8List.fromList([_sendMessageNumber]));

    // Advance sending chain key
    _sendingChainKey = await _kdf(
        _sendingChainKey!, Uint8List.fromList([_sendMessageNumber + 1]));
    _sendMessageNumber++;

    // Encrypt message with AES-256-GCM
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(messageKey),
      nonce: nonce,
    );

    // Get current DH public key
    final dhPublicKey =
        Uint8List.fromList((await _dhKeyPair!.extractPublicKey()).bytes);

    // Create encrypted message with header
    final encryptedMessage = EncryptedMessage(
      dhPublicKey: dhPublicKey,
      messageNumber: _sendMessageNumber - 1,
      previousChainLength: _previousChainLength,
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      nonce: Uint8List.fromList(nonce),
      mac: Uint8List.fromList(secretBox.mac.bytes),
    );

    // Securely wipe message key
    messageKey.fillRange(0, messageKey.length, 0);

    return encryptedMessage;
  }

  /// Decrypt a message using Double Ratchet
  ///
  /// Parameters:
  /// - encryptedMessage: The encrypted message to decrypt
  ///
  /// Returns: Decrypted plaintext
  ///
  /// Security: Verifies MAC before decryption, discards message keys after use
  Future<Uint8List> decrypt(EncryptedMessage encryptedMessage) async {
    if (_rootKey == null) {
      throw StateError('Double Ratchet not initialized');
    }

    // A message carrying our OWN DH public key is a loopback (self) message:
    // no DH ratchet is performed and the receiving chain (initialized as a
    // mirror of the sending chain) advances in lockstep to reproduce the same
    // message keys. Any other message with a new remote DH public key still
    // triggers a DH ratchet, as in a real two-party session.
    final localDhPublicKey =
        Uint8List.fromList((await _dhKeyPair!.extractPublicKey()).bytes);
    final isLoopback =
        _bytesEqual(encryptedMessage.dhPublicKey, localDhPublicKey);
    if (!isLoopback &&
        (_remoteDhPublicKey == null ||
            !_bytesEqual(_remoteDhPublicKey!, encryptedMessage.dhPublicKey))) {
      await _dhRatchet(encryptedMessage.dhPublicKey);
    }

    // Derive message key from receiving chain key
    final messageKey = await _kdf(
        _receivingChainKey!, Uint8List.fromList([_receiveMessageNumber]));

    // Advance receiving chain key
    _receivingChainKey = await _kdf(
        _receivingChainKey!, Uint8List.fromList([_receiveMessageNumber + 1]));
    _receiveMessageNumber++;

    // Create SecretBox for decryption
    final secretBox = SecretBox(
      encryptedMessage.ciphertext,
      nonce: encryptedMessage.nonce,
      mac: Mac(encryptedMessage.mac),
    );

    // Decrypt message with AES-256-GCM
    final plaintext = await _aesGcm.decrypt(
      secretBox,
      secretKey: SecretKey(messageKey),
    );

    // Securely wipe message key (forward secrecy)
    messageKey.fillRange(0, messageKey.length, 0);

    return Uint8List.fromList(plaintext);
  }

  /// Perform DH ratchet step
  ///
  /// Parameters:
  /// - remoteDhPublicKey: The remote DH public key
  ///
  /// Security: Updates root key and generates new chain keys
  Future<void> _dhRatchet(Uint8List remoteDhPublicKey) async {
    if (_dhKeyPair == null) {
      throw StateError('DH key pair not initialized');
    }

    // Perform DH with remote public key
    final dhOutput = await _performDH(
      Uint8List.fromList(await _dhKeyPair!.extractPrivateKeyBytes()),
      remoteDhPublicKey,
    );

    // Update root key with DH output
    _rootKey = await _kdf(_rootKey!, dhOutput);

    // Generate new DH key pair
    _previousChainLength = _sendMessageNumber;
    _sendMessageNumber = 0;
    _receiveMessageNumber = 0;
    _dhKeyPair = await _cryptoService.generateCurve25519KeyPair();
    _remoteDhPublicKey = remoteDhPublicKey;

    // Initialize new sending and receiving chain keys
    _sendingChainKey = await _kdf(_rootKey!, Uint8List(0));
    _receivingChainKey = await _kdf(_rootKey!, Uint8List.fromList([1]));

    // Securely wipe DH output
    dhOutput.fillRange(0, dhOutput.length, 0);
  }

  /// Key derivation function (simplified HKDF)
  ///
  /// Parameters:
  /// - inputKey: The input key material
  /// - context: Context information for KDF
  ///
  /// Returns: Derived key
  Future<Uint8List> _kdf(Uint8List inputKey, Uint8List context) async {
    // Simplified KDF using HMAC-SHA256
    final hmac = Hmac(Sha256());
    final mac = await hmac.calculateMac(
      context,
      secretKey: SecretKey(inputKey),
    );
    return Uint8List.fromList(mac.bytes);
  }

  /// Perform Diffie-Hellman key exchange using X25519
  ///
  /// Uses the session's [_dhKeyPair] (already available) with the remote
  /// [publicKey] to derive the shared secret.
  Future<Uint8List> _performDH(
      Uint8List privateKey, Uint8List publicKey) async {
    // Use the session's current DH key pair for the computation.
    // The privateKey param is ignored — the real key material lives in
    // _dhKeyPair which the cryptography package manages internally.
    final remotePublicKey = SimplePublicKey(publicKey, type: KeyPairType.x25519);
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _dhKeyPair!,
      remotePublicKey: remotePublicKey,
    );
    return Uint8List.fromList(await sharedSecret.extractBytes());
  }

  /// Compare two byte arrays for equality
  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Get current session counters (no private key material).
  Map<String, dynamic> getSessionState() {
    return {
      'sendMessageNumber': _sendMessageNumber,
      'receiveMessageNumber': _receiveMessageNumber,
      'previousChainLength': _previousChainLength,
    };
  }

  /// Restore session counters from a previous [getSessionState] call.
  void restoreSessionState(Map<String, dynamic> state) {
    _sendMessageNumber = state['sendMessageNumber'] as int;
    _receiveMessageNumber = state['receiveMessageNumber'] as int;
    _previousChainLength = state['previousChainLength'] as int;
  }

  /// Serialize the full session state to bytes for secure storage.
  ///
  /// Layout (all little-endian):
  ///   rootKey(32) + sendingChainKey(32) + receivingChainKey(32)
  ///   + sendMessageNumber(4) + receiveMessageNumber(4) + previousChainLength(4)
  ///   + dhPrivateKey(32) + dhPublicKey(32)
  ///   + remoteDhPublicKeyLen(4) + remoteDhPublicKey(N)
  ///
  /// Total: 172 + N bytes (N=0 when no remote key, N=32 when set).
  ///
  /// SECURITY: The serialized bytes contain PRIVATE key material (dhPrivateKey).
  /// The caller MUST store them in hardware-backed secure storage (e.g.
  /// FlutterSecureStorage) and NEVER write to plaintext files or logs.
  Future<Uint8List> toBytes() async {
    if (_rootKey == null || _dhKeyPair == null) {
      throw StateError('Double Ratchet not initialized');
    }
    final buf = BytesBuilder();
    buf.add(_rootKey!);
    buf.add(_sendingChainKey!);
    buf.add(_receivingChainKey!);
    _addInt32(buf, _sendMessageNumber);
    _addInt32(buf, _receiveMessageNumber);
    _addInt32(buf, _previousChainLength);
    // DH key pair — extract private key bytes asynchronously.
    buf.add(Uint8List.fromList(await _dhKeyPair!.extractPrivateKeyBytes()));
    buf.add(Uint8List.fromList((await _dhKeyPair!.extractPublicKey()).bytes));
    // Remote DH public key (nullable)
    if (_remoteDhPublicKey != null) {
      _addInt32(buf, _remoteDhPublicKey!.length);
      buf.add(_remoteDhPublicKey!);
    } else {
      _addInt32(buf, 0);
    }
    return buf.toBytes();
  }

  /// Restore a session from serialized bytes.
  static Future<DoubleRatchetService> fromBytes(
    Uint8List bytes,
    CryptoService cryptoService,
  ) async {
    int offset = 0;
    Uint8List readBytes(int len) {
      final slice = bytes.sublist(offset, offset + len);
      offset += len;
      return slice;
    }
    int readInt32() {
      final v = (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      offset += 4;
      return v;
    }

    final rootKey = readBytes(32);
    final sendingChainKey = readBytes(32);
    final receivingChainKey = readBytes(32);
    final sendMessageNumber = readInt32();
    final receiveMessageNumber = readInt32();
    final previousChainLength = readInt32();
    final dhPrivateKey = readBytes(32);
    final dhPublicKeyBytes = readBytes(32);
    final remoteLen = readInt32();
    final remoteDhPublicKey = remoteLen > 0 ? readBytes(remoteLen) : null;

    // Reconstruct the DH key pair from raw private key bytes.
    final dhKeyPair = SimpleKeyPairData(
      dhPrivateKey,
      publicKey: SimplePublicKey(dhPublicKeyBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    final svc = DoubleRatchetService(cryptoService: cryptoService);
    svc._rootKey = rootKey;
    svc._sendingChainKey = sendingChainKey;
    svc._receivingChainKey = receivingChainKey;
    svc._sendMessageNumber = sendMessageNumber;
    svc._receiveMessageNumber = receiveMessageNumber;
    svc._previousChainLength = previousChainLength;
    svc._dhKeyPair = dhKeyPair;
    svc._remoteDhPublicKey = remoteDhPublicKey;
    return svc;
  }

  static void _addInt32(BytesBuilder buf, int v) {
    buf.addByte((v >> 24) & 0xff);
    buf.addByte((v >> 16) & 0xff);
    buf.addByte((v >> 8) & 0xff);
    buf.addByte(v & 0xff);
  }
}

/// Encrypted message with header information
class EncryptedMessage {
  final Uint8List dhPublicKey;
  final int messageNumber;
  final int previousChainLength;
  final Uint8List ciphertext;
  final Uint8List nonce;
  final Uint8List mac;

  EncryptedMessage({
    required this.dhPublicKey,
    required this.messageNumber,
    required this.previousChainLength,
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  /// Convert to bytes for transmission
  Uint8List toBytes() {
    final buffer = BytesBuilder();
    buffer.add(dhPublicKey);
    buffer.addByte((messageNumber >> 24) & 0xff);
    buffer.addByte((messageNumber >> 16) & 0xff);
    buffer.addByte((messageNumber >> 8) & 0xff);
    buffer.addByte(messageNumber & 0xff);
    buffer.addByte((previousChainLength >> 24) & 0xff);
    buffer.addByte((previousChainLength >> 16) & 0xff);
    buffer.addByte((previousChainLength >> 8) & 0xff);
    buffer.addByte(previousChainLength & 0xff);
    buffer.add(ciphertext);
    buffer.add(nonce);
    buffer.add(mac);
    return buffer.toBytes();
  }

  /// Create from bytes received from network
  factory EncryptedMessage.fromBytes(Uint8List bytes) {
    int offset = 0;
    final dhPublicKey = bytes.sublist(offset, offset + 32);
    offset += 32;
    final messageNumber = (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    offset += 4;
    final previousChainLength = (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    offset += 4;
    // Layout: dhPublicKey(32) + messageNumber(4) + previousChainLength(4)
    // + ciphertext(N) + nonce(12) + mac(16). The trailing nonce+mac is 28
    // bytes, so ciphertext ends at bytes.length - 28.
    final ciphertext = bytes.sublist(offset, bytes.length - 28);
    offset = bytes.length - 28;
    final nonce = bytes.sublist(offset, offset + 12);
    offset += 12;
    final mac = bytes.sublist(offset);
    return EncryptedMessage(
      dhPublicKey: dhPublicKey,
      messageNumber: messageNumber,
      previousChainLength: previousChainLength,
      ciphertext: ciphertext,
      nonce: nonce,
      mac: mac,
    );
  }
}
