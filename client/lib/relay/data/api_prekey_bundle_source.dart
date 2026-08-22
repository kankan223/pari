import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../signal/models.dart';
import '../../signal/prekey_bundle_source.dart';

/// Fetches peer X3DH prekey bundles from the identity service API.
///
/// This implementation replaces the in-memory stub for production use.
/// Lookups are keyed by the peer's 64-hex blind hash; returning null means
/// "no bundle published" — the caller degrades gracefully.
///
/// SECURITY CHECKPOINT: only public key material is transmitted; private
/// keys never leave the device. The API endpoint requires authentication
/// so bundles cannot be scraped anonymously.
class ApiPreKeyBundleSource implements PreKeyBundleSource {
  final String baseUrl;
  final Future<String?> Function() tokenProvider;

  ApiPreKeyBundleSource({
    required this.baseUrl,
    required this.tokenProvider,
  });

  @override
  Future<PreKeyBundle?> fetchFor(String peerBlindHash) async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) return null;

    try {
      final url = Uri.parse('$baseUrl/v1/identity/prekeys/$peerBlindHash');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        return null; // No bundle published for this peer
      }

      if (response.statusCode != 200) {
        return null; // Server error — degrade gracefully
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseBundle(json);
    } catch (_) {
      // Network error, timeout, etc. — degrade gracefully.
      return null;
    }
  }

  PreKeyBundle? _parseBundle(Map<String, dynamic> json) {
    try {
      final identityKey = _base64Decode(json['identity_key'] as String);
      final signedPreKeyId = json['signed_pre_key_id'] as int;
      final signedPreKey = _base64Decode(json['signed_pre_key'] as String);
      final signedPreKeySignature =
          _base64Decode(json['signed_pre_key_signature'] as String);

      // The server atomically consumes one OTPK and returns it in
      // `consumed_one_time_pre_key`. The initiator MUST use this key
      // for the X3DH session.
      Uint8List? oneTimePreKey;
      int? oneTimePreKeyId;
      final consumed = json['consumed_one_time_pre_key'] as Map<String, dynamic>?;
      if (consumed != null) {
        oneTimePreKey = _base64Decode(consumed['public_key'] as String);
        oneTimePreKeyId = consumed['key_id'] as int;
      }

      return PreKeyBundle(
        registrationId: '', // Not used by the initiator
        identityKey: identityKey,
        signedPreKeyId: signedPreKeyId,
        signedPreKey: signedPreKey,
        signedPreKeySignature: signedPreKeySignature,
        oneTimePreKeyId: oneTimePreKeyId,
        oneTimePreKey: oneTimePreKey,
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _base64Decode(String data) {
    // Try standard base64 first, then base64url.
    try {
      return Uint8List.fromList(base64Decode(data));
    } catch (_) {
      return Uint8List.fromList(base64Url.decode(data));
    }
  }
}
