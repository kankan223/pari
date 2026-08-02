import 'dart:convert';
import 'dart:typed_data';

/// Public key bundle for sharing with other users
/// 
/// This structure contains all public keys needed for X3DH handshake
/// and is shared via the backend server (never contains private keys)
class PreKeyBundle {
  final String registrationId;
  final Uint8List identityKey;
  final int signedPreKeyId;
  final Uint8List signedPreKey;
  final Uint8List signedPreKeySignature;
  final int? oneTimePreKeyId;
  final Uint8List? oneTimePreKey;

  PreKeyBundle({
    required this.registrationId,
    required this.identityKey,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    this.oneTimePreKeyId,
    this.oneTimePreKey,
  });

  /// Convert to JSON for API transmission
  Map<String, dynamic> toJson() {
    return {
      'registrationId': registrationId,
      'identityKey': _base64Encode(identityKey),
      'signedPreKeyId': signedPreKeyId,
      'signedPreKey': _base64Encode(signedPreKey),
      'signedPreKeySignature': _base64Encode(signedPreKeySignature),
      if (oneTimePreKeyId != null) 'oneTimePreKeyId': oneTimePreKeyId,
      if (oneTimePreKey != null) 'oneTimePreKey': _base64Encode(oneTimePreKey!),
    };
  }

  /// Create from JSON received from API
  factory PreKeyBundle.fromJson(Map<String, dynamic> json) {
    return PreKeyBundle(
      registrationId: json['registrationId'] as String,
      identityKey: _base64Decode(json['identityKey'] as String),
      signedPreKeyId: json['signedPreKeyId'] as int,
      signedPreKey: _base64Decode(json['signedPreKey'] as String),
      signedPreKeySignature: _base64Decode(json['signedPreKeySignature'] as String),
      oneTimePreKeyId: json['oneTimePreKeyId'] as int?,
      oneTimePreKey: json['oneTimePreKey'] != null 
          ? _base64Decode(json['oneTimePreKey'] as String) 
          : null,
    );
  }

  static String _base64Encode(Uint8List data) {
    return base64Encode(data);
  }

  static Uint8List _base64Decode(String data) {
    return Uint8List.fromList(base64Decode(data));
  }
}

/// Signed prekey with metadata
class SignedPreKey {
  final int keyId;
  final Uint8List publicKey;
  final Uint8List privateKey;
  final DateTime createdAt;
  final DateTime expiresAt;

  SignedPreKey({
    required this.keyId,
    required this.publicKey,
    required this.privateKey,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Check if this prekey needs rotation (older than 7 days)
  bool needsRotation() {
    return DateTime.now().isAfter(expiresAt);
  }
}

/// One-time prekey with metadata
class OneTimePreKey {
  final int keyId;
  final Uint8List publicKey;
  final Uint8List privateKey;

  OneTimePreKey({
    required this.keyId,
    required this.publicKey,
    required this.privateKey,
  });
}
