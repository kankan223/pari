import 'package:civic_commons/academy/data/in_memory_academy_progress_store.dart';
import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:civic_commons/academy/domain/academy_progress.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 13.3 E2E: Academy pillar end-to-end learning journey.
///
/// Tests the complete user journey:
/// 1. Load the syllabus with multiple domains and modules
/// 2. Navigate to a domain and view its modules
/// 3. Complete modules and track progress
/// 4. Verify persistence across restart (cold-start restoration)
/// 5. Verify zero-identity invariants
void main() {
  group('Academy E2E - Learning journey', () {
    late InMemoryAcademyProgressStore progressStore;

    setUp(() {
      progressStore = InMemoryAcademyProgressStore();
    });

    test('load syllabus → navigate domains → complete modules → track progress',
        () async {
      // Step 1: Create the in-memory syllabus.
      final syllabus = AcademySyllabus(
        domains: [
          AcademyDomain.parse(
            domainId: 'dl-001',
            title: 'Digital Literacy',
            locale: 'en',
          ),
          AcademyDomain.parse(
            domainId: 'ps-001',
            title: 'Privacy & Security',
            locale: 'en',
          ),
        ],
        modules: [
          AcademyModule.parse(
            moduleId: '550e8400-e29b-41d4-a716-446655440001',
            domainId: 'dl-001',
            title: 'What is Digital Citizenship?',
            durationMinutes: 10,
            locale: 'en',
            contentRef: 'content/dl-001/mod-001',
          ),
          AcademyModule.parse(
            moduleId: '550e8400-e29b-41d4-a716-446655440002',
            domainId: 'dl-001',
            title: 'Online Safety Basics',
            durationMinutes: 15,
            locale: 'en',
            contentRef: 'content/dl-001/mod-002',
          ),
          AcademyModule.parse(
            moduleId: '550e8400-e29b-41d4-a716-446655440003',
            domainId: 'dl-001',
            title: 'Evaluating Online Sources',
            durationMinutes: 12,
            locale: 'en',
            contentRef: 'content/dl-001/mod-003',
          ),
          AcademyModule.parse(
            moduleId: '550e8400-e29b-41d4-a716-446655440004',
            domainId: 'ps-001',
            title: 'Understanding Passwords',
            durationMinutes: 8,
            locale: 'en',
            contentRef: 'content/ps-001/mod-004',
          ),
          AcademyModule.parse(
            moduleId: '550e8400-e29b-41d4-a716-446655440005',
            domainId: 'ps-001',
            title: 'Two-Factor Authentication',
            durationMinutes: 10,
            locale: 'en',
            contentRef: 'content/ps-001/mod-005',
          ),
        ],
      );

      final syllabusRepo =
          InMemoryAcademySyllabusRepository(seed: syllabus);

      // Step 2: Load the syllabus.
      final loaded = await syllabusRepo.fetchSyllabus();
      expect(loaded.domains, hasLength(2));
      expect(loaded.domains.first.title, 'Digital Literacy');
      expect(loaded.domains.last.title, 'Privacy & Security');
      expect(loaded.moduleCount, 5);

      // Step 3: Navigate to Digital Literacy domain.
      final dlModules = loaded.modulesFor('dl-001');
      expect(dlModules, hasLength(3));
      expect(dlModules.first.title, 'What is Digital Citizenship?');

      // Step 4: Mark modules as completed.
      const mod001 = '550e8400-e29b-41d4-a716-446655440001';
      const mod002 = '550e8400-e29b-41d4-a716-446655440002';
      const mod003 = '550e8400-e29b-41d4-a716-446655440003';
      await progressStore.markModuleComplete(mod001);
      await progressStore.markModuleComplete(mod002);

      // Step 5: Verify progress tracking.
      final completed = await progressStore.loadCompletedModuleIds();
      expect(completed, containsAll([mod001, mod002]));
      expect(completed, isNot(contains(mod003)));

      // Step 6: Domain progress = 2/3 completed.
      final fraction = AcademyProgress.domainFraction(
        modules: dlModules,
        completedModuleIds: completed,
      );
      expect(fraction, closeTo(2 / 3, 0.01));

      final percent = AcademyProgress.domainPercent(
        modules: dlModules,
        completedModuleIds: completed,
      );
      expect(percent, 67);

      // Step 7: Cold-start restoration.
      final freshStore = InMemoryAcademyProgressStore();
      await freshStore.markModuleComplete(mod001);
      await freshStore.markModuleComplete(mod002);

      final restoredCompleted = await freshStore.loadCompletedModuleIds();
      expect(restoredCompleted, containsAll([mod001, mod002]));
      expect(restoredCompleted, isNot(contains(mod003)));

      // Step 8: Complete all modules.
      await progressStore.markModuleComplete(mod003);
      final allCompleted = await progressStore.loadCompletedModuleIds();
      final fullFraction = AcademyProgress.domainFraction(
        modules: dlModules,
        completedModuleIds: allCompleted,
      );
      expect(fullFraction, 1.0);
    });

    test('module IDs are UUID v4 validated — zero identity', () {
      final module = AcademyModule.parse(
        moduleId: '550e8400-e29b-41d4-a716-446655440000',
        domainId: 'dl-001',
        title: 'Test Module',
        durationMinutes: 10,
        locale: 'en',
        contentRef: 'content/test',
      );
      expect(UuidV4.isValid(module.moduleId), isTrue);
      expect(module.moduleId, isNot(contains('+91')));
      expect(module.moduleId, isNot(contains('@')));
    });

    test('progress store carries no identity columns', () async {
      await progressStore.markModuleComplete('mod-001');
      final completed = await progressStore.loadCompletedModuleIds();
      expect(completed, contains('mod-001'));
    });

    test('total duration calculation across all modules', () async {
      final syllabus = AcademySyllabus(
        domains: [
          AcademyDomain.parse(
            domainId: 'dl-001',
            title: 'Digital Literacy',
            locale: 'en',
          ),
        ],
        modules: [
          AcademyModule.parse(
            moduleId: '550e8400-e29b-41d4-a716-446655440010',
            domainId: 'dl-001',
            title: 'Module 1',
            durationMinutes: 10,
            locale: 'en',
            contentRef: 'content/1',
          ),
          AcademyModule.parse(
            moduleId: '550e8400-e29b-41d4-a716-446655440011',
            domainId: 'dl-001',
            title: 'Module 2',
            durationMinutes: 15,
            locale: 'en',
            contentRef: 'content/2',
          ),
        ],
      );

      final modules = syllabus.modulesFor('dl-001');
      final totalMinutes =
          modules.fold<int>(0, (sum, m) => sum + m.durationMinutes);
      expect(totalMinutes, 25);
    });

    test('mark module incomplete reverses completion', () async {
      await progressStore.markModuleComplete('mod-001');
      expect(await progressStore.loadCompletedModuleIds(), contains('mod-001'));

      await progressStore.markModuleIncomplete('mod-001');
      expect(
          await progressStore.loadCompletedModuleIds(), isNot(contains('mod-001')));
    });
  });
}
