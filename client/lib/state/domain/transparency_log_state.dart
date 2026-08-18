import '../../transparency/domain/transparency_record.dart';

/// Transparency log phases (Task 10.5).
enum TransparencyLogPhase {
  /// Not started.
  idle,

  /// Reading the local log.
  loading,

  /// The records + integrity status are projected.
  ready,

  /// A local source failed — generic, payload-free error.
  error,
}

/// Immutable state projection for the Transparency Log (Task 10.5).
///
/// Carries the records list (oldest first), the integrity verification
/// status, and the record count. The UI reads from this state and calls
/// the BLoC to trigger transitions.
///
/// SECURITY CHECKPOINT (10.5):
/// - [records] contains only [TransparencyRecord] objects with
///   public-label summaries and fixed action labels — no blind hashes,
///   no identity, no PII.
/// - The error state carries no payload (generic message only).
class TransparencyLogState {
  final TransparencyLogPhase phase;
  final List<TransparencyRecord> records;
  final bool integrityValid;
  final int recordCount;
  final String? errorMessage;

  const TransparencyLogState({
    this.phase = TransparencyLogPhase.idle,
    this.records = const [],
    this.integrityValid = true,
    this.recordCount = 0,
    this.errorMessage,
  });
}
