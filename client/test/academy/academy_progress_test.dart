import 'dart:io';

import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:civic_commons/academy/domain/academy_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final syllabus = InMemoryAcademySyllabusRepository.seedSyllabus;
  final civicsModules = syllabus.modulesFor('civics'); // 2 modules
  final techModules = syllabus.modulesFor('tech'); // 1 module
  final allIds = syllabus.modules.map((m) => m.moduleId).toSet();

  group('AcademyProgress (Task 9.1)', () {
    test('empty completion → 0% everywhere', () {
      expect(
        AcademyProgress.overallPercent(
            syllabus: syllabus, completedModuleIds: const {}),
        0,
      );
      expect(
        AcademyProgress.domainPercent(
            modules: civicsModules, completedModuleIds: const {}),
        0,
      );
      expect(
        AcademyProgress.domainFraction(
            modules: civicsModules, completedModuleIds: const {}),
        0.0,
      );
    });

    test('full completion → 100% everywhere', () {
      expect(
        AcademyProgress.overallPercent(
            syllabus: syllabus, completedModuleIds: allIds),
        100,
      );
      expect(
        AcademyProgress.domainPercent(
            modules: civicsModules, completedModuleIds: allIds),
        100,
      );
      expect(
        AcademyProgress.domainPercent(
            modules: techModules, completedModuleIds: allIds),
        100,
      );
    });

    test('partial completion is deterministic (1 of 2 → 50%)', () {
      final oneCivics = {civicsModules.first.moduleId};
      expect(
        AcademyProgress.domainPercent(
            modules: civicsModules, completedModuleIds: oneCivics),
        50,
      );
      expect(
        AcademyProgress.domainPercent(
            modules: techModules, completedModuleIds: oneCivics),
        0,
      );
      // 1 of 3 overall → 33%.
      expect(
        AcademyProgress.overallPercent(
            syllabus: syllabus, completedModuleIds: oneCivics),
        33,
      );
    });

    test('fraction clamps to 1.0 for over-complete sets (idempotent)', () {
      // A completed set larger than the module list still yields 1.0.
      expect(
        AcademyProgress.domainFraction(
            modules: civicsModules, completedModuleIds: allIds),
        1.0,
      );
    });

    test('empty module list never divides by zero', () {
      expect(
        AcademyProgress.domainFraction(
            modules: const [], completedModuleIds: const {}),
        0.0,
      );
      expect(
        AcademyProgress.overallFraction(
            syllabus: const AcademySyllabus(domains: [], modules: []),
            completedModuleIds: const {}),
        0.0,
      );
    });

    test('orphanModuleIds surfaces stale/forged keys only', () {
      final orphans = AcademyProgress.orphanModuleIds(
        syllabus: syllabus,
        completedModuleIds: {
          ...allIds,
          '00000000-0000-4000-8000-000000000000', // forged
          '11111111-1111-4111-8111-111111111111', // stale
        },
      );
      expect(orphans, hasLength(2));
      expect(orphans, contains('00000000-0000-4000-8000-000000000000'));
      expect(orphans, isNot(contains('3f2504e0-4f89-41d3-9a0c-0305e82c3301')));
    });
    test('progress is a pure function of module ids — no identity inputs', () {
      // Structural: the projection API takes ONLY a syllabus (public course
      // content) + a set of UUID module ids. There is no identity-typed
      // parameter to even attempt (compiler-enforced zero-PII).
      final source = _codeOf('lib/academy/domain/academy_progress.dart');
      // Declared identifiers only — the doc comment may mention the words.
      final declarations =
          RegExp(r'\bfinal\s+[\w<>?]+\s+(\w+);|\b(\w+)\s+\w+\s+[({]')
              .allMatches(source)
              .map((m) => ((m.group(1) ?? m.group(2)) ?? '').toLowerCase())
              .toList();
      expect(declarations, isNot(contains('phone')));
      expect(declarations, isNot(contains('email')));
      expect(declarations, isNot(contains('blindhash')));
      expect(declarations, isNot(contains('name')));
    });
  });
}

String _codeOf(String path) {
  // Read with the repo-relative path (tests run from client/).
  return File(path).readAsStringSync();
}
