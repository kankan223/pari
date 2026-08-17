import 'dart:typed_data';

import 'offline_module_cache.dart';

/// A locally-persisted offline-cache row (Task 9.4).
///
/// Persisted inside the encrypted SQLCipher database (`module_cache` table,
/// schema v11). The row is written FIRST (offline-first) when a download is
/// queued, so the queue intent survives a cold restart; the sealed content
/// lands in the same row when the download completes.
///
/// SECURITY CHECKPOINT (Task 9.4): the record is keyed by a validated UUID
/// v4 module id and carries ONLY a status wire name, sizes, an opaque
/// timestamp and — when downloaded — the AES-256-GCM SEALED content payload.
/// Zero plaintext content and zero identity ever touch the row.
class ModuleCacheRecord {
  /// The module's validated UUID v4 id (cache key — zero identity).
  final String moduleId;

  /// Current lifecycle status (strict wire name).
  final OfflineCacheStatus status;

  /// Nominal manifest size (offline budget for this module).
  final int totalBytes;

  /// Bytes actually available offline (== totalBytes when downloaded).
  final int cachedBytes;

  /// Unix-ms timestamp when the download completed (null until then).
  final int? downloadedAt;

  /// AES-256-GCM SEALED content payload (only present when downloaded).
  final Uint8List? sealedPayload;

  /// Unix-ms timestamp when the sealed payload was written.
  final int? cachedAt;

  const ModuleCacheRecord({
    required this.moduleId,
    required this.status,
    required this.totalBytes,
    required this.cachedBytes,
    this.downloadedAt,
    this.sealedPayload,
    this.cachedAt,
  });

  ModuleCacheEntry toEntry() => ModuleCacheEntry(
        moduleId: moduleId,
        status: status,
        totalBytes: totalBytes,
        cachedBytes: cachedBytes,
        downloadedAt: downloadedAt,
      );

  ModuleCacheRecord copyWith({
    OfflineCacheStatus? status,
    int? cachedBytes,
    int? downloadedAt,
    Uint8List? sealedPayload,
    bool clearSealedPayload = false,
    int? cachedAt,
  }) =>
      ModuleCacheRecord(
        moduleId: moduleId,
        status: status ?? this.status,
        totalBytes: totalBytes,
        cachedBytes: cachedBytes ?? this.cachedBytes,
        downloadedAt: downloadedAt ?? this.downloadedAt,
        sealedPayload:
            clearSealedPayload ? null : (sealedPayload ?? this.sealedPayload),
        cachedAt: cachedAt ?? this.cachedAt,
      );
}
