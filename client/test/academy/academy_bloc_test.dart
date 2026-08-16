import 'package:civic_commons/academy/data/in_memory_academy_progress_store.dart';
import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:civic_commons/academy/domain/academy_progress_store.dart';
import 'package:civic_commons/academy/domain/academy_syllabus_repository.dart';
import 'package:civic_commons/state/data/local_academy_bloc.dart';
import 'package:civic_commons/state/domain/academy_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted [AcademySyllabusRepository]: fails [failures] times, then
/// serves the seed syllabus (recovery path).
class _ScriptedRepository implements AcademySyllabusRepository {
  _ScriptedRepository({this.failures = 0});

  int failures;
  int calls = 0;

  @override
  Future<AcademySyllabus> fetchSyllabus() async {
    calls++;
    if (calls <= failures) {
      throw StateError('boom');
    }
    return InMemoryAcademySyllabusRepository.seedSyllabus;
  }
}

/// Scripted [AcademyProgressStore] fake.
class _ScriptedProgressStore implements AcademyProgressStore {
  final Set<String> seeded = <String>{};
  final List<String> completions = <String>[];

  @override
  Future<Set<String>> loadCompletedModuleIds() async => Set.of(seeded);

  @override
  Future<void> markModuleComplete(String moduleId) async {
    seeded.add(moduleId);
    completions.add(moduleId);
  }

  @override
  Future<void> markModuleIncomplete(String moduleId) async {
    seeded.remove(moduleId);
  }
}

void main() {
  group('LocalAcademyBloc (Phase 9 foundation)', () {
    test('start loads the syllabus + persisted progress into ready', () async {
      final bloc = LocalAcademyBloc(
        repository: InMemoryAcademySyllabusRepository(),
        store: _ScriptedProgressStore(),
      );
      final states = <AcademyState>[];
      final sub = bloc.state.listen(states.add);

      await bloc.start();
      await pumpEventQueue();

      expect(states.first.phase, AcademyPhase.loading);
      expect(states.last.phase, AcademyPhase.ready);
      expect(states.last.isReady, isTrue);
      expect(states.last.moduleCount, greaterThanOrEqualTo(3));
      expect(states.last.totalMinutes, greaterThan(0));

      await sub.cancel();
      await bloc.close();
    });

    test('start surfaces a GENERIC error on repository failure', () async {
      final failing = _ScriptedRepository(failures: 1);
      final bloc = LocalAcademyBloc(
        repository: failing,
        store: InMemoryAcademyProgressStore(),
      );
      final states = <AcademyState>[];
      final sub = bloc.state.listen(states.add);

      await bloc.start();
      await pumpEventQueue();

      expect(states.last.phase, AcademyPhase.failure);
      expect(states.last.syllabus, isNull);
      // The generic message never contains the underlying error detail.
      expect(states.last.errorMessage, isNotEmpty);
      expect(states.last.errorMessage.contains('boom'), isFalse);

      await sub.cancel();
      await bloc.close();
    });

    test('retry recovers after a transient failure', () async {
      final failing = _ScriptedRepository(failures: 1);
      final bloc = LocalAcademyBloc(
        repository: failing,
        store: InMemoryAcademyProgressStore(),
      );
      final states = <AcademyState>[];
      final sub = bloc.state.listen(states.add);

      await bloc.start();
      await pumpEventQueue();
      expect(states.last.phase, AcademyPhase.failure);

      // The repository has recovered — a retry succeeds and reaches ready.
      await bloc.retry();
      await pumpEventQueue();
      expect(states.last.phase, AcademyPhase.ready);
      expect(states.last.moduleCount, greaterThanOrEqualTo(3));
      expect(failing.calls, 2);

      await sub.cancel();
      await bloc.close();
    });

    test('toggleModuleComplete flips progress and persists it', () async {
      const moduleId = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
      final store = _ScriptedProgressStore();
      final bloc = LocalAcademyBloc(
        repository: InMemoryAcademySyllabusRepository(),
        store: store,
      );
      final states = <AcademyState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start();
      await pumpEventQueue();

      await bloc.toggleModuleComplete(moduleId);
      await pumpEventQueue();
      expect(states.last.completedModuleIds, contains(moduleId));
      expect(store.completions, contains(moduleId));

      await bloc.toggleModuleComplete(moduleId);
      await pumpEventQueue();
      expect(states.last.completedModuleIds, isNot(contains(moduleId)));
      expect(await store.loadCompletedModuleIds(), isEmpty);

      await sub.cancel();
      await bloc.close();
    });

    test('progress survives a cold restart through the store', () async {
      const moduleId = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
      final store = InMemoryAcademyProgressStore();
      await store.markModuleComplete(moduleId);

      final bloc = LocalAcademyBloc(
        repository: InMemoryAcademySyllabusRepository(),
        store: store,
      );
      final states = <AcademyState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start();
      await pumpEventQueue();

      expect(states.last.phase, AcademyPhase.ready);
      expect(states.last.completedModuleIds, contains(moduleId));

      await sub.cancel();
      await bloc.close();
    });
  });
}
