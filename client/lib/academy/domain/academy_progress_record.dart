/// A locally-persisted Academy progress row (Task 9.2).
///
/// The learner's completed-module set, persisted inside the encrypted
/// database. The row is written FIRST (offline-first) so progress survives
/// a cold restart before any sync ever happens.
///
/// SECURITY CONTRACT (Task 9.2): the record carries a SINGLE UUID v4 module
/// id — zero identity. The `UuidV4` guard on [AcademyModule.parse] rejects
/// anything that is not a well-formed UUID v4 before a module can exist, so
/// a phone, name, handle or hash can never be a progress key. There is no
/// timestamp, no device marker, no telemetry column.
class AcademyProgressRecord {
  /// The completed module's UUID v4 id.
  final String moduleId;

  const AcademyProgressRecord({required this.moduleId});
}
