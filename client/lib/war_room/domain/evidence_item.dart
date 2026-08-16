import 'dart:typed_data';

/// A file the victim picked for a case (Task 8.2).
///
/// [displayName] is the raw file name from the picker — it is a DISPLAY-ONLY
/// transient: it is NEVER persisted, never queued, never logged, and never
/// rendered (filenames can embed sensitive context). The UI shows only the
/// [mimeType] + [sizeBytes] label.
///
/// SECURITY CHECKPOINT (Task 8.2): the pick result is the ONLY place the raw
/// name exists — it dies when the pick completes and is replaced by the
/// [EvidenceRecord] projection below.
class PickedEvidence {
  final Uint8List bytes;
  final String displayName;
  final String mimeType;
  final int sizeBytes;

  const PickedEvidence({
    required this.bytes,
    required this.displayName,
    required this.mimeType,
    required this.sizeBytes,
  });
}

/// A human-safe label derived from mime + size — the ONLY evidence
/// presentation that reaches the UI (e.g. `Photo · 1.2 MB`). No filename,
/// no path, no identity.
String evidenceLabel(String mimeType, int sizeBytes) {
  final kind = switch (mimeType.split('/').first) {
    'image' => 'Photo',
    'video' => 'Video',
    'audio' => 'Audio',
    'text' => 'Document',
    _ => 'File',
  };
  return '$kind · ${_humanSize(sizeBytes)}';
}

String _humanSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The durable, locally persisted evidence row (Task 8.2).
///
/// SECURITY CHECKPOINT (Task 8.2): the row carries ONLY non-sensitive
/// metadata (size, mime, timestamp, case stamp) + opaque ciphertext blobs
/// ([sealedFile] = AES-256-GCM(file, DEK); [dekEnvelope] = the WRAPPED DEK).
/// There is NO filename column, no path, no identity — a filename that
/// embeds sensitive context can never touch the database.
class EvidenceRecord {
  /// UUID v4 id — doubles as the idempotency key for the sync transport.
  final String id;

  final String caseNumber;

  /// Encrypted file bytes — AES-256-GCM under the per-item DEK.
  final Uint8List sealedFile;

  /// Serialized [DekEnvelope] — the DEK wrapped to the recipient public key.
  final Uint8List dekEnvelope;

  final int sizeBytes;
  final String mimeType;
  final DateTime createdAt;

  const EvidenceRecord({
    required this.id,
    required this.caseNumber,
    required this.sealedFile,
    required this.dekEnvelope,
    required this.sizeBytes,
    required this.mimeType,
    required this.createdAt,
  });
}
