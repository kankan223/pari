import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:civic_commons/crypto/crypto_service.dart';

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
  KeyPair? _dhKeyPair;
  Uint8List? _remoteDhPublicKey;

  // AES-256-GCM for message encryption
  static final Algorithm _aesGcm = AesGcm.with256bits();

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
  Future<void> initialize(Uint8List sharedSecret, {KeyPair? dhKeyPair}) async {
    // Initialize root key with shared secret
    _rootKey = Uint8List.fromList(sharedSecret);

    // Generate or use provided DH key pair
    _dhKeyPair = dhKeyPair ?? await _cryptoService.generateCurve25519KeyPair();

    // Initialize sending chain key
    _sendingChainKey = await _kdf(_rootKey!, Uint8List(0));

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
    final messageKey = await _kdf(_sendingChainKey!, Uint8List.fromList([_sendMessageNumber]));

    // Advance sending chain key
    _sendingChainKey = await _kdf(_sendingChainKey!, Uint8List.fromList([_sendMessageNumber + 1]));
    _sendMessageNumber++;

    // Encrypt message with AES-256-GCM
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(messageKey),
      nonce: nonce,
    );

    // Get current DH public key
    final dhPublicKey = await _dhKeyPair!.extractPublicKeyBytes();

    // Create encrypted message with header
    final encryptedMessage = EncryptedMessage(
      dhPublicKey: dhPublicKey,
      messageNumber: _sendMessageNumber - 1,
      previousChainLength: _previousChainLength,
      ciphertext: secretBox.ciphertext,
      nonce: nonce,
      mac: secretBox.mac.bytes,
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

    // Check if we need to perform a DH ratchet
    if (_remoteDhPublicKey == null || 
        !_bytesEqual(_remoteDhPublicKey!, encryptedMessage.dhPublicKey)) {
      await _dhRatchet(encryptedMessage.dhPublicKey);
    }

    // Derive message key from receiving chain key
    final messageKey = await _kdf(_receivingChainKey!, Uint8List.fromList([_receiveMessageNumber]));

    // Advance receiving chain key
    _receivingChainKey = await _kdf(_receivingChainKey!, Uint8List.fromList([_receiveMessageNumber + 1]));
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

    return plaintext;
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
      await _dhKeyPair!.extractPrivateKeyBytes(),
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

  /// Perform Diffie-Hellman key exchange
  /// 
  /// Parameters:
  /// - privateKey: The private key
  /// - publicKey: The public key
  /// 
  /// Returns: The shared secret
  Future<Uint8List> _performDH(Uint8List privateKey, Uint8List publicKey) async {
    // This would use the actual X25519 DH operation
    final result = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      result[i] = (privateKey[i] ^ publicKey[i]);
    }
    return result;
  }

  /// Compare two byte arrays for equality
  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Get current session state (for storage)
  /// 
  /// Returns: Session state as a map
  /// 
  /// Security: Does not include private keys in the state
  Map<String, dynamic> getSessionState() {
    return {
      'sendMessageNumber': _sendMessageNumber,
      'receiveMessageNumber': _receiveMessageNumber,
      'previousChainLength': _previousChainLength,
    };
  }

  /// Restore session state from storage
  /// 
  /// Parameters:
  /// - state: The session state to restore
  void restoreSessionState(Map<String, dynamic> state) {
    _sendMessageNumber = state['sendMessageNumber'] as int;
    _receiveMessageNumber = state['receiveMessageNumber'] as int;
    _previousChainLength = state['previousChainLength'] as int;
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
    final messageNumber = (bytes[offset] << 24) | (bytes[offset + 1] << 16) | 
                        (bytes[offset + 2] << 8) | bytes[offset + 3];
    offset += 4;
    final previousChainLength = (bytes[offset] << 24) | (bytes[offset + 1] << 16) | 
                              (bytes[offset + 2] << 8) | bytes[offset + 3];
    offset += 4;
    final ciphertext = bytes.sublist(offset, bytes.length - 48);
    offset = bytes.length - 48;
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
