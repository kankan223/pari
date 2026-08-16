import '../../ledger/domain/ledger_category.dart';
import 'ledger_compose_state.dart';

/// BLoC for the Ledger compose flow (Task 7.1).
///
/// Collects the draft (category, pin code, headline, body), validates it
/// against FR-L1 (exactly one pin code + one category), and persists it
/// locally through the offline-first queue. The UI binds to [state] only.
///
/// SECURITY CHECKPOINT (Task 7.1): the draft is civic content — the bloc
/// never touches identity or PII, and the persisted draft is sealed by the
/// queue cipher at rest.
abstract class LedgerComposeBloc {
  /// Stream of compose states.
  Stream<LedgerComposeState> get state;

  /// The latest emitted state (non-stream read for submit confirmation).
  LedgerComposeState get current;

  /// Starts the flow (idle).
  Future<void> start();

  /// Updates the selected category.
  Future<void> setCategory(LedgerCategory? category);

  /// Updates the pin code field.
  Future<void> setPinCode(String pinCode);

  /// Updates the headline field.
  Future<void> setHeadline(String headline);

  /// Updates the body field.
  Future<void> setBody(String body);

  /// Validates and persists the draft. Emits submitting → submitted, or
  /// error when invalid (missing category/pin/headline, or malformed pin).
  Future<void> submit();

  /// Resets to a fresh idle draft.
  Future<void> reset();

  /// Releases resources.
  Future<void> close();
}
