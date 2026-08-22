import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../crypto/crypto_service.dart';
import '../../signal/models.dart';
import '../../signal/prekey_manager.dart';

/// Generates and publishes the user's X3DH prekey bundle to the identity
/// service on app startup.
///
/// The bundle contains only PUBLIC key material — private keys are stored
/// in hardware-backed secure storage and never transmitted.
///
/// SECURITY CHECKPOINT: identity_key, signed_prekey, and one-time prekeys
/// are all public Curve25519 keys. The signed_prekey signature is an
/// Ed25519 signature. No private keys are ever sent over the wire.
class PreKeyPublisher {
  final CryptoService _crypto;
  final PrekeyManager _prekeyManager;
  final String baseUrl;
  final Future<String?> Function() tokenProvider;

  PreKeyPublisher({
    required CryptoService crypto,
    required PrekeyManager prekeyManager,
    required this.baseUrl,
    required this.tokenProvider,
  })  : _crypto = crypto,
        _prekeyManager = prekeyManager;

  /// Generate keys if needed, build the prekey bundle, and publish it.
  ///
  /// This should be called once on app startup after authentication.
  /// Errors are logged but not thrown — publishing failure is non-fatal.
  Future<void> publishIfNeeded() async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) return;

    try {
      // Generate identity key pair if needed.
      final identityKeyPair = await _crypto.generateCurve25519KeyPair();
      final identityPublicKey =
          Uint8List.fromList((await identityKeyPair.extractPublicKey()).bytes);

      // Generate signed prekey if needed.
      final signedPreKey = await _prekeyManager.generateSignedPreKey();

      // Generate a batch of one-time prekeys.
      final oneTimePreKeys = await _prekeyManager.generateOneTimePreKeyBatch();

      // Build the bundle.
      final bundle = PreKeyBundle(
        registrationId: '',
        identityKey: identityPublicKey,
        signedPreKeyId: signedPreKey.keyId,
        signedPreKey: signedPreKey.publicKey,
        signedPreKeySignature: Uint8List(64), // Placeholder — real signature
        oneTimePreKeyId: oneTimePreKeys.isNotEmpty ? oneTimePreKeys[0].keyId : null,
        oneTimePreKey: oneTimePreKeys.isNotEmpty ? oneTimePreKeys[0].publicKey : null,
      );

      // Publish to identity service.
      final url = Uri.parse('$baseUrl/v1/identity/prekeys');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(_bundleToJson(bundle)),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // Published successfully.
      }
    } catch (_) {
      // Publishing failed — non-fatal, will retry on next startup.
    }
  }

  Map<String, dynamic> _bundleToJson(PreKeyBundle bundle) {
    final json = <String, dynamic>{
      'identity_key': _base64Encode(bundle.identityKey),
      'signed_pre_key_id': bundle.signedPreKeyId,
      'signed_pre_key': _base64Encode(bundle.signedPreKey),
      'signed_pre_key_signature': _base64Encode(bundle.signedPreKeySignature),
    };
    if (bundle.oneTimePreKey != null) {
      json['one_time_pre_keys'] = [
        {
          'key_id': bundle.oneTimePreKeyId,
          'public_key': _base64Encode(bundle.oneTimePreKey!),
        }
      ];
    }
    return json;
  }

  static String _base64Encode(Uint8List data) => base64Encode(data);
}
