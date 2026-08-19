import 'audit_log_state.dart';

/// BLoC for the Audit Logging System (Task 11.2).
///
/// The UI binds to [state] and calls [refresh]/[verifyIntegrity] — it
/// never talks to the audit repository directly.
///
/// SECURITY CHECKPOINT (11.2): [AuditLogState] carries only public-label
/// summaries and fixed action labels. No phone number, no blind hash,
/// no identity can appear in state; error states carry no payload at all.
abstract class AuditLogBloc {
  /// Stream of audit log states (idle → loading → ready | error).
  Stream<AuditLogState> get state;

  /// The current state (for late subscribers).
  AuditLogState get current;

  /// Loads audit records and transitions to ready.
  Future<void> refresh();

  /// Verifies the SHA-256 chain integrity.
  Future<void> verifyIntegrity();

  /// Releases resources.
  Future<void> close();
}
