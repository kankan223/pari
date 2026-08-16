import '../domain/academy_progress_store.dart';

/// In-memory [AcademyProgressStore] (Phase 9 foundation scaffold,
/// Task 8.8).
///
/// Progress is keyed ONLY by UUID module ids. The production
/// implementation persists to the local encrypted store (SQLCipher) and
/// seals progress updates through the sync queue.
class InMemoryAcademyProgressStore implements AcademyProgressStore {
  final Set<String> _completed = <String>{};

  @override
  Future<Set<String>> loadCompletedModuleIds() async =>
      Set<String>.unmodifiable(_completed);

  @override
  Future<void> markModuleComplete(String moduleId) async {
    _completed.add(moduleId);
  }

  @override
  Future<void> markModuleIncomplete(String moduleId) async {
    _completed.remove(moduleId);
  }
}
