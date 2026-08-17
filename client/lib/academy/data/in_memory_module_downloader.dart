import 'dart:typed_data';

import '../../repository/domain/queue_payload_cipher.dart';
import '../domain/offline_module_cache.dart';

/// Deterministic in-process [ModuleDownloader] (Task 9.4).
///
/// The Academy tree imports NO networking — this seam stands in for the
/// Phase-9 content delivery (presigned MinIO / R2 / Bunny, TECHSTACK §9.1)
/// until the production downloader lands. It fabricates a deterministic
/// opaque plaintext (sized to the manifest budget), SEALS it with the
/// injected AES-256-GCM [QueuePayloadCipher], then ZEROES the plaintext
/// buffer (memory hygiene) — so ONLY ciphertext ever reaches the cache.
///
/// SECURITY CHECKPOINT (Task 9.4): the plaintext is derived from the module
/// id hash (a UUID — zero identity) and is wiped in place after sealing;
/// the returned payload is sealed bytes only.
class SimulatedModuleDownloader implements ModuleDownloader {
  final QueuePayloadCipher _cipher;

  SimulatedModuleDownloader({required QueuePayloadCipher cipher})
      : _cipher = cipher;

  @override
  Future<Uint8List> downloadModuleContent(
      String moduleId, int totalBytes) async {
    // Deterministic opaque plaintext derived from the (UUID) module id —
    // never from user data, sized to the manifest budget. The id is ASCII,
    // so its code units ARE its bytes (no crypto dependency needed to build
    // a stable byte seed).
    final seed = moduleId.codeUnits;
    final plaintext = Uint8List(totalBytes);
    for (var i = 0; i < totalBytes; i++) {
      plaintext[i] = seed[i % seed.length];
    }
    try {
      return await _cipher.seal(plaintext);
    } finally {
      // MEMORY HYGIENE: zero the plaintext buffer unconditionally, even if
      // sealing throws, so no plaintext lingers in memory.
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }
}
