import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'evidence_envelope.dart';
import 'evidence_item.dart';

/// Port for the evidence cryptography pipeline (Task 8.2).
///
/// Every evidence file is sealed under a fresh per-item Data Encryption Key
/// (DEK); the DEK itself is never stored or queued in plaintext — it is
/// WRAPPED to a recipient public key so only a holder of the matching
/// private key can re-open the evidence. The server therefore only ever sees
/// sealed files + wrapped DEKs (SECURITY CHECKPOINT: evidence never
/// decrypts server-side).
abstract class EvidenceCipher {
  /// Generates a fresh 32-byte DEK for one evidence item.
  Future<Uint8List> generateDek();

  /// Seals [plaintext] (file bytes) with [dek] using AES-256-GCM.
  Future<Uint8List> sealFile(Uint8List plaintext, Uint8List dek);

  /// Opens [sealed] with [dek]. Throws on authentication failure.
  Future<Uint8List> openFile(Uint8List sealed, Uint8List dek);

  /// Wraps [dek] to [recipient] (X25519-ECDH + AES-256-GCM) so it can
  /// travel beside the sealed file without opening it.
  Future<DekEnvelope> wrapDek(
    Uint8List dek, {
    required SimplePublicKey recipient,
  });

  /// Unwraps [envelope] with [keyPair]; returns the plaintext DEK.
  Future<Uint8List> unwrapDek(
    DekEnvelope envelope, {
    required SimpleKeyPair keyPair,
  });
}

/// Port for picking a local file (Task 8.2).
///
/// The production implementation wraps the `file_picker` plugin; tests
/// inject an in-memory fake. Returns null when the victim cancels.
abstract class EvidencePicker {
  Future<PickedEvidence?> pick();
}

/// Port for the evidence persistence seam (Task 8.2).
///
/// Offline-first: the encrypted evidence record is written to the local
/// store IMMEDIATELY, then a sealed sync item is queued. Returns the
/// evidence id (UUID v4 — the sync idempotency key).
abstract class EvidenceSink {
  Future<String> addEvidence(String caseNumber, PickedEvidence evidence);

  /// Cold-restart recovery snapshot of locally persisted evidence.
  Future<List<EvidenceRecord>> localEvidence();

  /// Removes locally persisted evidence (e.g. case withdrawn).
  Future<void> removeEvidence(String evidenceId);
}
