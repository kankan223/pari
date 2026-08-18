import 'transparency_log_state.dart';

/// BLoC for the Transparency Log (Task 10.5).
///
/// The UI binds to [state] and calls [refresh]/[verifyIntegrity] — it
/// never talks to the transparency repository directly.
///
/// SECURITY CHECKPOINT (10.5): [TransparencyLogState] carries only the
/// public records list (public-label summaries + fixed action labels) +
/// integrity status + record count. No blind hash, no identity, no PII
/// can appear in state; error states carry no payload at all.
abstract class TransparencyLogBloc {
  /// Stream of transparency log states (idle → loading → ready | error).
  Stream<TransparencyLogState> get state;

  /// The current state (for late subscribers).
  TransparencyLogState get current;

  /// Re-reads the transparency log and projects records + integrity status.
  Future<void> refresh();

  /// Verifies the SHA-256 chain integrity and updates [current.integrityValid].
  Future<void> verifyIntegrity();

  /// Releases resources.
  Future<void> close();
}
