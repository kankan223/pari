import '../../academy/domain/academy_module.dart';

/// Lifecycle of the Academy syllabus loading (Phase 9 foundation
/// scaffold, Task 8.8).
enum AcademyPhase {
  /// No load attempted yet.
  idle,

  /// Loading the local syllabus snapshot.
  loading,

  /// Syllabus is available and the UI can render.
  ready,

  /// The syllabus could not be loaded — generic error state.
  failure,
}

/// Immutable BLoC state for the Academy (Phase 9 foundation scaffold,
/// Task 8.8).
///
/// SECURITY CHECKPOINT (Phase 9): the state carries ONLY public course
/// content + UUID module ids + locale tags — no phones, names, emails or
/// hashes ever reach the UI through this projection. [errorMessage] is
/// always the SAME generic string (no side channel, no reason-specific
/// detail).
class AcademyState {
  final AcademyPhase phase;

  /// The local syllabus snapshot (null until ready).
  final AcademySyllabus? syllabus;

  /// UUID module ids the learner has completed (non-PII keys).
  final Set<String> completedModuleIds;

  /// Generic failure message — constant, never content-specific.
  final String errorMessage;

  const AcademyState({
    this.phase = AcademyPhase.idle,
    this.syllabus,
    this.completedModuleIds = const {},
    this.errorMessage = '',
  });

  bool get isReady => phase == AcademyPhase.ready;

  int get moduleCount => syllabus?.moduleCount ?? 0;

  /// Total minutes across all syllabus modules (a public stat, not PII).
  int get totalMinutes {
    final s = syllabus;
    if (s == null) {
      return 0;
    }
    return s.modules.fold(0, (sum, m) => sum + m.durationMinutes);
  }

  AcademyState copyWith({
    AcademyPhase? phase,
    AcademySyllabus? syllabus,
    bool clearSyllabus = false,
    Set<String>? completedModuleIds,
    String? errorMessage,
  }) =>
      AcademyState(
        phase: phase ?? this.phase,
        syllabus: clearSyllabus ? null : (syllabus ?? this.syllabus),
        completedModuleIds: completedModuleIds ?? this.completedModuleIds,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}
