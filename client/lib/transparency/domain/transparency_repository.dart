import 'transparency_record.dart';

/// Repository port for the Transparency Log (Task 10.5).
///
/// All operations are local-first and offline-safe. The repository is
/// APPEND-ONLY — there is no update or delete API. [verifyIntegrity]
/// recomputes the entire SHA-256 chain and reports any tampering.
///
/// SECURITY CHECKPOINT (10.5): the repository carries only
/// [TransparencyRecord] objects with public-label summaries and fixed
/// action types — no identity, no PII, no tokens.
abstract class TransparencyRepository {
  /// Returns all records for [pinCode], ordered by sequence (oldest first).
  Future<List<TransparencyRecord>> getByPinCode(String pinCode);

  /// Returns the total record count for [pinCode].
  Future<int> getCount(String pinCode);

  /// Appends a new record. The caller must provide a UUID v4 [recordId]
  /// and pre-computed [prevHash]/[selfHash]. The repository validates
  /// that seq is exactly next-in-seq for the pinCode.
  Future<void> append(TransparencyRecord record);

  /// Recomputes the SHA-256 chain for [pinCode] and returns true if
  /// every link is valid. Returns false if any record was tampered,
  /// reordered, or removed.
  Future<bool> verifyIntegrity(String pinCode);
}
