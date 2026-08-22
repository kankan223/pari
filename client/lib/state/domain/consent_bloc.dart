import '../../consent/domain/consent_type.dart';
import 'consent_state.dart';

/// BLoC for DPDP Consent (Task 11.1).
///
/// The UI binds to [state] and calls [grantAll]/[withdrawAll]/
/// [withdrawConsent]/[deleteData] — it never talks to the consent
/// repository directly.
///
/// SECURITY CHECKPOINT (11.1): [ConsentState] carries only boolean
/// consent flags and fixed type labels. No phone number, no blind
/// hash, no identity can appear in state; error states carry no
/// payload at all.
abstract class ConsentBloc {
  /// Stream of consent states (idle → loading → ready | error).
  Stream<ConsentState> get state;

  /// The current state (for late subscribers).
  ConsentState get current;

  /// Checks current consent status and transitions to ready.
  Future<void> refresh();

  /// Grants consent for all required types.
  Future<void> grantAll();

  /// Grants consent for a single [type].
  Future<void> grantConsent(ConsentType type);

  /// Withdraws consent for all types and triggers data deletion.
  Future<void> withdrawAll();

  /// Withdraws consent for a single [type].
  Future<void> withdrawConsent(ConsentType type);

  /// Triggers data deletion on consent withdrawal (DPDP §8).
  Future<void> deleteData();

  /// Releases resources.
  Future<void> close();
}
