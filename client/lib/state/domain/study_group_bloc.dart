import '../../academy/domain/study_group.dart';
import 'study_group_state.dart';

/// BLoC for cross-pillar study groups (Task 9.6).
///
/// Loads the module-anchored group snapshot through the
/// [StudyGroupRepository] port (offline-first — always the local encrypted
/// store), runs the deterministic [StudyGroupMatcher] against the learner's
/// coarse pin scope + locale + module interests, and drives browsing,
/// creation and joining. The UI binds to [state] and never touches the
/// repository directly.
///
/// SECURITY CHECKPOINT (Task 9.6): state carries only module-anchored
/// groups + blinded `SG-####` memberships (UUID ids, public titles, coarse
/// pin scope, topic refs, match scores) — never identity, never PII.
abstract class StudyGroupBloc {
  /// Stream of study group states.
  Stream<StudyGroupState> get state;

  /// The latest emitted state (non-stream read for navigation wiring).
  StudyGroupState get current;

  /// Loads the group snapshot for [moduleId] and runs the deterministic
  /// matcher with the learner's coarse [pinCode] scope + [locale].
  Future<void> start({
    required String moduleId,
    required String pinCode,
    required String locale,
  });

  /// Retries loading after a failure.
  Future<void> retry();

  /// Filters the group list by [query] (case-insensitive title substring).
  void search(String query);

  /// Creates a study group anchored on the module.
  Future<void> createGroup({
    required String title,
    required List<StudyTopicRef> topics,
    required int capacity,
  });

  /// Joins [groupId] as this device's blinded handle.
  Future<void> joinGroup(String groupId);

  /// Releases resources.
  Future<void> close();
}
