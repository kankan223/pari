import 'dart:async';

import '../../academy/domain/academy_progress_store.dart';
import '../../academy/domain/academy_syllabus_repository.dart';
import '../domain/academy_bloc.dart';
import '../domain/academy_state.dart';

/// Local [AcademyBloc] (data layer, Phase 9 foundation scaffold,
/// Task 8.8).
///
/// Loads the syllabus snapshot from the local repository (offline-first —
/// the Academy never blocks on the network) and restores persisted
/// progress. Progress toggles are applied locally and written through the
/// [AcademyProgressStore]; the sync enqueue lands with Task 9.x.
class LocalAcademyBloc implements AcademyBloc {
  static const String _genericError = 'Unable to load the syllabus. '
      'Please try again.';

  final AcademySyllabusRepository _repository;
  final AcademyProgressStore _store;

  final StreamController<AcademyState> _controller =
      StreamController<AcademyState>.broadcast();

  AcademyState _current = const AcademyState();

  /// Monotonic sequence — a stale load can never overwrite a fresher one
  /// (codebase convention, cf. Task 6.2/7.2).
  int _seq = 0;

  LocalAcademyBloc({
    required AcademySyllabusRepository repository,
    required AcademyProgressStore store,
  })  : _repository = repository,
        _store = store;

  @override
  Stream<AcademyState> get state => _controller.stream;

  /// The latest emitted state (non-stream read for navigation wiring,
  /// mirroring [LocalLedgerComposeBloc.current]).
  @override
  AcademyState get current => _current;

  @override
  Future<void> start() async {
    _current = const AcademyState(phase: AcademyPhase.loading);
    _controller.add(_current);
    await _load();
  }

  @override
  Future<void> retry() async {
    _current = _current.copyWith(phase: AcademyPhase.loading);
    _controller.add(_current);
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    try {
      final syllabus = await _repository.fetchSyllabus();
      final completed = await _store.loadCompletedModuleIds();
      if (seq != _seq) {
        return; // stale load — a newer call superseded us.
      }
      _current = AcademyState(
        phase: AcademyPhase.ready,
        syllabus: syllabus,
        completedModuleIds: completed,
      );
    } catch (_) {
      if (seq != _seq) {
        return;
      }
      _current = _current.copyWith(
        phase: AcademyPhase.failure,
        clearSyllabus: true,
        errorMessage: _genericError,
      );
    }
    _controller.add(_current);
  }

  @override
  Future<void> toggleModuleComplete(String moduleId) async {
    final completed = Set<String>.from(_current.completedModuleIds);
    if (completed.contains(moduleId)) {
      completed.remove(moduleId);
      await _store.markModuleIncomplete(moduleId);
    } else {
      completed.add(moduleId);
      await _store.markModuleComplete(moduleId);
    }
    _current = _current.copyWith(completedModuleIds: completed);
    _controller.add(_current);
  }

  @override
  Future<void> close() => _controller.close();
}
