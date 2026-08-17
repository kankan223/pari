import '../../academy/domain/study_group.dart';

/// Lifecycle of the study group view (Task 9.6).
enum StudyGroupPhase {
  /// No load attempted yet.
  idle,

  /// Loading the local group snapshot.
  loading,

  /// The groups are available and the UI can render.
  ready,

  /// The groups could not be loaded — generic error state.
  failure,
}

/// Immutable BLoC state for cross-pillar study groups (Task 9.6).
///
/// SECURITY CHECKPOINT (Task 9.6): the state carries ONLY groups + local
/// memberships (UUID v4 ids, public titles, locale tags, the coarse pin
/// scope, cross-pillar topic refs, blinded `SG-####` handles, timestamps)
/// and deterministic match results — never identity, never PII.
/// [errorMessage] is always the SAME generic string (no side channel).
class StudyGroupState {
  final StudyGroupPhase phase;

  /// The anchor Academy module (validated UUID v4 — groups are
  /// module-anchored).
  final String moduleId;

  /// Every group for the module, newest-created first.
  final List<StudyGroup> groups;

  /// The local device's membership rows (blinded `SG-####` handles).
  final List<StudyGroupMember> memberships;

  /// The learner's coarse civic scope used for matching.
  final String pinCode;

  /// The learner's locale tag used for matching.
  final String locale;

  /// The live title search/filter query.
  final String query;

  /// [groups] filtered by [query] (case-insensitive title substring).
  final List<StudyGroup> filteredGroups;

  /// The deterministic match ranking against the learner's interests
  /// ([StudyGroupMatcher]) — best match first.
  final List<StudyGroupMatch> matches;

  /// Generic failure message — constant, never content-specific.
  final String errorMessage;

  const StudyGroupState({
    this.phase = StudyGroupPhase.idle,
    this.moduleId = '',
    this.groups = const [],
    this.memberships = const [],
    this.pinCode = '',
    this.locale = '',
    this.query = '',
    this.filteredGroups = const [],
    this.matches = const [],
    this.errorMessage = '',
  });

  bool get isReady => phase == StudyGroupPhase.ready;

  /// Whether the local device has already joined [groupId].
  bool hasJoined(String groupId) =>
      memberships.any((m) => m.groupId == groupId);

  /// The deterministic blinded handle for the anchor module.
  String get participantHandle =>
      moduleId.isEmpty ? '' : StudyGroupHandle.forModule(moduleId);

  StudyGroupState copyWith({
    StudyGroupPhase? phase,
    String? moduleId,
    List<StudyGroup>? groups,
    List<StudyGroupMember>? memberships,
    String? pinCode,
    String? locale,
    String? query,
    List<StudyGroup>? filteredGroups,
    List<StudyGroupMatch>? matches,
    String? errorMessage,
  }) =>
      StudyGroupState(
        phase: phase ?? this.phase,
        moduleId: moduleId ?? this.moduleId,
        groups: groups ?? this.groups,
        memberships: memberships ?? this.memberships,
        pinCode: pinCode ?? this.pinCode,
        locale: locale ?? this.locale,
        query: query ?? this.query,
        filteredGroups: filteredGroups ?? this.filteredGroups,
        matches: matches ?? this.matches,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}
