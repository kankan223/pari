import 'dart:async';

import '../../academy/domain/study_group.dart';
import '../domain/study_group_bloc.dart';
import '../domain/study_group_state.dart';

/// Local [StudyGroupBloc] (data layer, Task 9.6).
///
/// Loads the module-anchored group snapshot from the local
/// [StudyGroupRepository] port (offline-first — always the encrypted local
/// store), runs the deterministic [StudyGroupMatcher] against the learner's
/// coarse pin scope + locale + module interests, and drives browsing /
/// search / create / join through it. Every mutation re-reads the local
/// snapshot so the UI reflects the persisted state immediately.
class LocalStudyGroupBloc implements StudyGroupBloc {
  static const String _genericError =
      'Unable to load study groups. Please try again.';

  final StudyGroupRepository _repository;

  final StreamController<StudyGroupState> _controller =
      StreamController<StudyGroupState>.broadcast();

  StudyGroupState _current = const StudyGroupState();

  /// Monotonic sequence — a stale load can never overwrite a fresher one
  /// (codebase convention).
  int _seq = 0;

  LocalStudyGroupBloc({required StudyGroupRepository repository})
      : _repository = repository;

  @override
  Stream<StudyGroupState> get state => _controller.stream;

  /// The latest emitted state (non-stream read for navigation wiring).
  @override
  StudyGroupState get current => _current;

  @override
  Future<void> start({
    required String moduleId,
    required String pinCode,
    required String locale,
  }) async {
    _current = StudyGroupState(
      phase: StudyGroupPhase.loading,
      moduleId: moduleId,
      pinCode: pinCode,
      locale: locale,
    );
    _controller.add(_current);
    await _load();
  }

  @override
  Future<void> retry() async {
    _current = _current.copyWith(phase: StudyGroupPhase.loading);
    _controller.add(_current);
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    try {
      final groups = await _repository.listGroups(moduleId: _current.moduleId);
      final memberships = <StudyGroupMember>[];
      for (final g in groups) {
        memberships.addAll(await _repository.listMembers(g.groupId));
      }
      if (seq != _seq) {
        return; // stale load — a newer call superseded us.
      }
      _current = _current.copyWith(
        phase: StudyGroupPhase.ready,
        groups: groups,
        memberships: memberships,
        filteredGroups: _applyQuery(groups, _current.query),
        matches: _match(groups),
      );
    } catch (_) {
      if (seq != _seq) {
        return;
      }
      _current = _current.copyWith(
        phase: StudyGroupPhase.failure,
        errorMessage: _genericError,
      );
    }
    _controller.add(_current);
  }

  /// The deterministic pin-code-based matcher against the learner's module
  /// interests (the anchor module + the module's own pillar topic refs).
  List<StudyGroupMatch> _match(List<StudyGroup> groups) {
    final interests = <StudyTopicRef>[
      StudyTopicRef.parse(
        pillar: StudyPillar.academy,
        topicId: _current.moduleId,
      ),
    ];
    return StudyGroupMatcher.match(
      interest: StudyGroupInterest(
        pinCode: _current.pinCode,
        locale: _current.locale,
        topics: interests,
      ),
      candidates: groups,
    );
  }

  @override
  void search(String query) {
    _current = _current.copyWith(
      query: query,
      filteredGroups: _applyQuery(_current.groups, query),
    );
    _controller.add(_current);
  }

  static List<StudyGroup> _applyQuery(List<StudyGroup> groups, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return groups;
    }
    return groups
        .where((g) => g.title.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Future<void> createGroup({
    required String title,
    required List<StudyTopicRef> topics,
    required int capacity,
  }) async {
    try {
      await _repository.createGroup(
        moduleId: _current.moduleId,
        title: title,
        locale: _current.locale,
        pinCode: _current.pinCode,
        topics: topics,
        capacity: capacity,
        initiatorHandle: _current.participantHandle,
      );
    } catch (_) {
      _current = _current.copyWith(
        phase: StudyGroupPhase.failure,
        errorMessage: _genericError,
      );
    }
    await _load(); // refresh the group list + memberships + matches.
  }

  @override
  Future<void> joinGroup(String groupId) async {
    try {
      await _repository.joinGroup(
        groupId: groupId,
        memberHandle: _current.participantHandle,
      );
    } catch (_) {
      _current = _current.copyWith(
        phase: StudyGroupPhase.failure,
        errorMessage: _genericError,
      );
    }
    await _load(); // refresh — the joined group's count + memberships update.
  }

  @override
  Future<void> close() => _controller.close();
}
