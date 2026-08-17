import 'academy_state.dart';

/// BLoC for the Academy (Phase 9 foundation scaffold, Task 8.8).
///
/// Loads the local syllabus snapshot through the [AcademySyllabusRepository]
/// port and tracks learner progress (completed module ids) through the
/// [AcademyProgressStore] port. The UI binds to [state] and never touches
/// repositories or stores directly.
///
/// SECURITY CHECKPOINT (Phase 9): state carries only public course content
/// and UUID module ids — progress keys are module ids, never identity.
abstract class AcademyBloc {
  /// Stream of Academy states.
  Stream<AcademyState> get state;

  /// The latest emitted state (non-stream read for navigation wiring,
  /// mirroring [LocalLedgerComposeBloc.current]).
  AcademyState get current;

  /// Loads the syllabus snapshot + persisted progress.
  Future<void> start();

  /// Retries loading after a failure.
  Future<void> retry();

  /// Toggles [moduleId] in the completed set (offline-first local update;
  /// the sync enqueue lands with Task 9.x).
  Future<void> toggleModuleComplete(String moduleId);

  /// Releases resources.
  Future<void> close();
}
