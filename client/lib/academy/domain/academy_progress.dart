import 'academy_module.dart';

/// Deterministic Academy progress projections (Phase 9, Task 9.1).
///
/// Pure functions over the syllabus tree + the learner's completed-module
/// id set (UUID v4 keys only). Everything here is a PUBLIC statistic:
/// per-domain completion, overall completion, module counts, total minutes.
/// No identity, no PII — the input is a set of module ids and the output
/// is a small count/percentage.
///
/// SECURITY CHECKPOINT (Task 9.1): progress keys are UUID v4 module ids —
/// a phone, name, handle or hash can never be a progress key, because the
/// [UuidV4] guard on [AcademyModule.parse] rejects anything that is not a
/// well-formed UUID v4 before a module can exist.
abstract final class AcademyProgress {
  /// Fraction of [modules] completed, 0.0–1.0 (0 for an empty list).
  static double domainFraction({
    required List<AcademyModule> modules,
    required Set<String> completedModuleIds,
  }) {
    if (modules.isEmpty) {
      return 0;
    }
    final done =
        modules.where((m) => completedModuleIds.contains(m.moduleId)).length;
    return done / modules.length;
  }

  /// Whole-number percent (0–100) of [modules] completed.
  static int domainPercent({
    required List<AcademyModule> modules,
    required Set<String> completedModuleIds,
  }) =>
      (domainFraction(
                modules: modules,
                completedModuleIds: completedModuleIds,
              ) *
              100)
          .round();

  /// Overall fraction across every module in [syllabus], 0.0–1.0.
  static double overallFraction({
    required AcademySyllabus syllabus,
    required Set<String> completedModuleIds,
  }) {
    final modules = syllabus.modules;
    if (modules.isEmpty) {
      return 0;
    }
    return domainFraction(
      modules: modules,
      completedModuleIds: completedModuleIds,
    );
  }

  /// Overall whole-number percent (0–100).
  static int overallPercent({
    required AcademySyllabus syllabus,
    required Set<String> completedModuleIds,
  }) =>
      (overallFraction(
                syllabus: syllabus,
                completedModuleIds: completedModuleIds,
              ) *
              100)
          .round();

  /// Completed-module ids that are NOT present in the syllabus (stale or
  /// forged keys). Deterministic ascending by id.
  static List<String> orphanModuleIds({
    required AcademySyllabus syllabus,
    required Set<String> completedModuleIds,
  }) {
    final known = syllabus.modules.map((m) => m.moduleId).toSet();
    final orphans = completedModuleIds.difference(known).toList()..sort();
    return orphans;
  }
}
