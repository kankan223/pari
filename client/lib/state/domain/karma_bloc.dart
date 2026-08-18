import '../../karma/domain/karma_action.dart';
import 'karma_state.dart';

/// BLoC for the Civic Karma Engine (Task 10.2).
///
/// The UI binds to [state] and calls [refresh]/[record] — it never talks to
/// the karma repository or event source directly.
///
/// SECURITY CHECKPOINT (10.2): [KarmaState] carries only the public balance
/// + tier + gate satisfaction + UI-safe activity projections (fixed action
/// labels + deltas + timestamps). A blind hash, an event id, or any payload
/// can never appear in state; error states carry no payload at all.
abstract class KarmaBloc {
  /// Stream of karma states (idle → loading → ready | error).
  Stream<KarmaState> get state;

  /// The current state (for late subscribers).
  KarmaState get current;

  /// Re-reads the ledger and projects balance + gates + recent activity.
  Future<void> refresh();

  /// Records a karma [action] for the local blind-hash actor and refreshes.
  /// Returns false when the action was rejected (e.g. malformed actor).
  Future<bool> record(KarmaAction action);

  /// Releases resources.
  Future<void> close();
}
