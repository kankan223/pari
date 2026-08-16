import 'academy_module.dart';

/// Syllabus persistence boundary (port) for the Academy (Phase 9
/// foundation scaffold, Task 8.8).
///
/// Dependencies depend ONLY on this abstract interface. The production
/// implementation is local-cache-first (offline-first): the syllabus tree
/// renders from the local snapshot and refreshes through the sync queue —
/// the Academy never blocks on the network.
///
/// SECURITY CONTRACT (Phase 9): the syllabus carries only public course
/// content + UUID module ids + locale tags — never raw identity.
abstract class AcademySyllabusRepository {
  /// Returns the local syllabus snapshot (domains + modules).
  Future<AcademySyllabus> fetchSyllabus();
}
