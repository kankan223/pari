import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/crypto_service.dart';
import 'double_ratchet_service.dart';
import 'session_store.dart';

/// Persistent [SessionStore] backed by hardware-backed secure storage.
///
/// Sessions are serialized to bytes (including DH private keys) and stored
/// in FlutterSecureStorage, which uses:
/// - Android Keystore (hardware-backed when available)
/// - iOS Keychain (first_unlock accessibility)
/// - macOS Keychain
/// - Linux/Windows: encrypted file via libsecret / Windows Credential Manager
///
/// SECURITY CHECKPOINT:
/// - Session bytes contain DH private keys → stored in hardware keystore only
/// - Keys are base64-encoded before storage (FlutterSecureStorage requirement)
/// - Peer blind hashes used as storage keys (no PII)
/// - Never logged, never written to plaintext files
class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage _secureStorage;
  final CryptoService _cryptoService;

  static const String _keyPrefix = 'signal_session_';

  SecureSessionStore({
    FlutterSecureStorage? secureStorage,
    required CryptoService cryptoService,
  })  : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _cryptoService = cryptoService;

  @override
  Future<DoubleRatchetService?> load(String peerBlindHash) async {
    try {
      final raw = await _secureStorage.read(key: '$_keyPrefix$peerBlindHash');
      if (raw == null || raw.isEmpty) return null;
      final bytes = base64Decode(raw);
      return DoubleRatchetService.fromBytes(bytes, _cryptoService);
    } catch (_) {
      // Corrupted or incompatible data — treat as no session.
      return null;
    }
  }

  @override
  Future<void> save(String peerBlindHash, DoubleRatchetService session) async {
    try {
      final bytes = await session.toBytes();
      await _secureStorage.write(
        key: '$_keyPrefix$peerBlindHash',
        value: base64Encode(bytes),
      );
      // Wipe the serialized bytes from memory.
      bytes.fillRange(0, bytes.length, 0);
    } catch (_) {
      // Storage failure — non-fatal; session stays in memory for this run.
    }
  }

  @override
  Future<void> delete(String peerBlindHash) async {
    await _secureStorage.delete(key: '$_keyPrefix$peerBlindHash');
  }

  /// Delete all stored sessions (duress PIN / account deletion).
  Future<void> deleteAll() async {
    // FlutterSecureStorage.deleteAll removes all keys for this app.
    await _secureStorage.deleteAll();
  }
}
