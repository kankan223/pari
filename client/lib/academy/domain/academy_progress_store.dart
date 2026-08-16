/// Learner progress persistence boundary (port) for the Academy (Phase 9
/// foundation scaffold, Task 8.8).
///
/// Progress is tracked ONLY by module id (UUID v4) — never by identity.
/// The production implementation persists to the local encrypted store
/// (SQLCipher) with sealed envelopes on the sync queue; the scaffold ships
/// an in-memory implementation.
///
/// SECURITY CONTRACT (Phase 9): progress keys are UUID module ids; no
/// phone, name, handle or hash ever enters this store.
abstract class AcademyProgressStore {
  /// Returns the ids of the modules the learner has completed.
  Future<Set<String>> loadCompletedModuleIds();

  /// Marks [moduleId] complete. Idempotent.
  Future<void> markModuleComplete(String moduleId);

  /// Removes [moduleId] from the completed set. Idempotent.
  Future<void> markModuleIncomplete(String moduleId);
}
