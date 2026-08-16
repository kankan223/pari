import 'dart:convert';
import 'dart:typed_data';

/// The WRAPPED Data Encryption Key (Task 8.2).
///
/// The DEK is a fresh 32-byte key per evidence item. It is wrapped with an
/// X25519-ECDH shared secret + AES-256-GCM so the envelope can travel
/// beside the sealed file WITHOUT opening it: a party holding only the
/// queue/envelope bytes gets sealed files + DEKs they cannot unwrap.
///
/// SECURITY CHECKPOINT (Task 8.2): the plaintext DEK is NEVER persisted or
/// queued — only this wrapped form is. [recipientFingerprint] identifies
/// WHICH public key can unwrap (analyst keys slot in here in Task 8.5).
class DekEnvelope {
  static const String alg = 'X25519-ECDH-AES256GCM';

  final String algorithm;
  final Uint8List wrappedDek;
  final String recipientFingerprint;

  const DekEnvelope({
    required this.algorithm,
    required this.wrappedDek,
    required this.recipientFingerprint,
  });

  /// Strict binary codec — version + length-prefixed fields.
  Uint8List toBytes() {
    final wrappedB = utf8.encode(_b64(wrappedDek));
    final fpB = utf8.encode(recipientFingerprint);
    final algB = utf8.encode(algorithm);
    final out = BytesBuilder();
    out.addByte(1); // version
    out.addByte(algB.length);
    out.add(algB);
    out.addByte(wrappedB.length);
    out.add(wrappedB);
    out.addByte(fpB.length);
    out.add(fpB);
    return out.toBytes();
  }

  static DekEnvelope fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('empty DEK envelope');
    }
    final reader = _Reader(bytes);
    final version = reader.byte();
    if (version != 1) {
      throw FormatException('unsupported DEK envelope version: $version');
    }
    final algorithm = utf8.decode(reader.bytes(reader.byte()));
    final wrappedDek = _unb64(utf8.decode(reader.bytes(reader.byte())));
    final fingerprint = utf8.decode(reader.bytes(reader.byte()));
    if (!reader.done) {
      throw const FormatException('trailing bytes in DEK envelope');
    }
    return DekEnvelope(
      algorithm: algorithm,
      wrappedDek: wrappedDek,
      recipientFingerprint: fingerprint,
    );
  }
}

/// The evidence transport envelope (Task 8.2).
///
/// Carries ONLY the sealed file + wrapped DEK + non-sensitive metadata.
/// Strict `v:1` bounds; decode rejects unknown versions / malformed shapes.
///
/// SECURITY CHECKPOINT (Task 8.2): NO filename, NO path, NO EXIF, NO
/// identity — the only user-derived bytes are the DEK-sealed file itself.
class EvidenceEnvelope {
  final String evidenceId;
  final String caseNumber;
  final int sizeBytes;
  final String mimeType;
  final DateTime createdAt;
  final Uint8List sealedFile;
  final Uint8List dekEnvelope;

  const EvidenceEnvelope({
    required this.evidenceId,
    required this.caseNumber,
    required this.sizeBytes,
    required this.mimeType,
    required this.createdAt,
    required this.sealedFile,
    required this.dekEnvelope,
  });

  Map<String, Object?> toJson() => {
        'v': 1,
        'evidence_id': evidenceId,
        'case_number': caseNumber,
        'size_bytes': sizeBytes,
        'mime_type': mimeType,
        'created_at': createdAt.microsecondsSinceEpoch,
        'sealed_file': _b64(sealedFile),
        'dek_envelope': _b64(dekEnvelope),
      };

  static EvidenceEnvelope fromJson(Map<String, Object?> json) {
    if (json['v'] != 1) {
      throw const FormatException('unsupported evidence envelope version');
    }
    final evidenceId = json['evidence_id'];
    final caseNumber = json['case_number'];
    final sizeBytes = json['size_bytes'];
    final mimeType = json['mime_type'];
    final createdAt = json['created_at'];
    final sealedFile = json['sealed_file'];
    final dekEnvelope = json['dek_envelope'];
    if (evidenceId is! String ||
        caseNumber is! String ||
        sizeBytes is! int ||
        sizeBytes < 0 ||
        mimeType is! String ||
        createdAt is! int ||
        sealedFile is! String ||
        dekEnvelope is! String) {
      throw const FormatException('malformed evidence envelope');
    }
    return EvidenceEnvelope(
      evidenceId: evidenceId,
      caseNumber: caseNumber,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      // Created-at is an absolute instant — preserve the UTC flag so
      // round-trips compare equal regardless of the host timezone.
      createdAt: DateTime.fromMicrosecondsSinceEpoch(createdAt, isUtc: true),
      sealedFile: _unb64(sealedFile),
      dekEnvelope: _unb64(dekEnvelope),
    );
  }
}

/// Serializes an [EvidenceEnvelope] to the wire frame.
Uint8List encodeEvidenceEnvelope(EvidenceEnvelope envelope) =>
    Uint8List.fromList(utf8.encode(jsonEncode(envelope.toJson())));

/// Parses a wire frame back into an [EvidenceEnvelope].
///
/// Strict: the payload must be a JSON object at the top level and decode via
/// [EvidenceEnvelope.fromJson] bounds.
EvidenceEnvelope decodeEvidenceEnvelope(Uint8List frame) {
  final decoded = jsonDecode(utf8.decode(frame));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('evidence envelope must be a JSON object');
  }
  return EvidenceEnvelope.fromJson(decoded);
}

class _Reader {
  final Uint8List _bytes;
  int _offset = 0;

  _Reader(this._bytes);

  bool get done => _offset >= _bytes.length;

  int byte() {
    if (_offset >= _bytes.length) {
      throw const FormatException('truncated DEK envelope');
    }
    return _bytes[_offset++];
  }

  Uint8List bytes(int length) {
    if (_offset + length > _bytes.length) {
      throw const FormatException('truncated DEK envelope field');
    }
    final out = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return out;
  }
}

String _b64(Uint8List bytes) => base64Encode(bytes);

Uint8List _unb64(String value) {
  try {
    return base64Decode(value);
  } on FormatException {
    throw const FormatException('invalid base64 in envelope');
  }
}
