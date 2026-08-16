import 'package:civic_commons/academy/data/in_memory_academy_progress_store.dart';
import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryAcademySyllabusRepository (Phase 9 foundation)', () {
    test('serves the deterministic seed syllabus', () async {
      final repo = InMemoryAcademySyllabusRepository();
      final a = await repo.fetchSyllabus();
      expect(a.moduleCount, greaterThanOrEqualTo(3));
      expect(a.domains, isNotEmpty);
    });

    test('is deterministic across invocations and instances', () async {
      final repoA = InMemoryAcademySyllabusRepository();
      final repoB = InMemoryAcademySyllabusRepository();
      final a = await repoA.fetchSyllabus();
      final b = await repoB.fetchSyllabus();
      expect(a.modules.map((m) => m.moduleId).toList(),
          b.modules.map((m) => m.moduleId).toList());
      expect(a.modules.first.title, b.modules.first.title);
    });

    test('accepts an injected seed syllabus', () async {
      final custom = AcademySyllabus(
        domains: [
          AcademyDomain.parse(
              domainId: 'civics', title: 'Civic Education', locale: 'en'),
        ],
        modules: [
          AcademyModule.parse(
            moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
            domainId: 'civics',
            title: 'only module',
            durationMinutes: 5,
            locale: 'en',
            contentRef: 'civics/only',
          ),
        ],
      );
      final repo = InMemoryAcademySyllabusRepository(seed: custom);
      final syllabus = await repo.fetchSyllabus();
      expect(syllabus.moduleCount, 1);
      expect(syllabus.modules.single.title, 'only module');
    });
  });

  group('InMemoryAcademyProgressStore (Phase 9 foundation)', () {
    test('round-trips completed module ids', () async {
      final store = InMemoryAcademyProgressStore();
      expect(await store.loadCompletedModuleIds(), isEmpty);

      await store.markModuleComplete('3f2504e0-4f89-41d3-9a0c-0305e82c3301');
      await store.markModuleComplete('3f2504e0-4f89-41d3-9a0c-0305e82c3302');
      final completed = await store.loadCompletedModuleIds();
      expect(completed, hasLength(2));
      expect(completed, contains('3f2504e0-4f89-41d3-9a0c-0305e82c3301'));
    });

    test('markModuleIncomplete is idempotent and removes', () async {
      final store = InMemoryAcademyProgressStore();
      await store.markModuleComplete('3f2504e0-4f89-41d3-9a0c-0305e82c3301');
      await store.markModuleIncomplete('3f2504e0-4f89-41d3-9a0c-0305e82c3301');
      await store.markModuleIncomplete('3f2504e0-4f89-41d3-9a0c-0305e82c3301');
      expect(await store.loadCompletedModuleIds(), isEmpty);
    });
  });
}
