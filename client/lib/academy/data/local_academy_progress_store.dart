import '../../repository/domain/entity_store.dart';
import '../domain/academy_progress_record.dart';
import '../domain/academy_progress_store.dart';

/// Production [AcademyProgressStore] (Task 9.2 Syllabus Tree).
///
/// Persists the learner's completed-module set inside the encrypted
/// SQLCipher database (`academy_progress` table — schema v10). Written
/// FIRST (offline-first): a completion toggle lands in the local row before
/// anything else, so progress survives a cold restart.
///
/// SECURITY CHECKPOINT (Task 9.2): the row holds ONLY the UUID v4 module
/// id (row presence = completed) — zero identity columns, no timestamp, no
/// device marker, no telemetry. The `UuidV4` guard on
/// [AcademyModule.parse] rejects anything that is not a well-formed UUID
/// v4 before a module can exist, so a phone/name/handle/hash can never be
/// a progress key.
class LocalAcademyProgressStore implements AcademyProgressStore {
  final EntityStore<AcademyProgressRecord> _store;

  LocalAcademyProgressStore({required EntityStore<AcademyProgressRecord> store})
      : _store = store;

  @override
  Future<Set<String>> loadCompletedModuleIds() async {
    final rows = await _store.getAll();
    return rows.map((r) => r.moduleId).toSet();
  }

  @override
  Future<void> markModuleComplete(String moduleId) async {
    // INSERT OR REPLACE semantics (SqliteEntityStore) — idempotent.
    await _store.insert(AcademyProgressRecord(moduleId: moduleId));
  }

  @override
  Future<void> markModuleIncomplete(String moduleId) async {
    // DELETE of an absent row is a no-op — idempotent.
    await _store.delete(moduleId);
  }
}
