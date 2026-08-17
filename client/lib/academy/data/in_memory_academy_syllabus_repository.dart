import '../domain/academy_module.dart';
import '../domain/academy_syllabus_repository.dart';
import 'local_academy_syllabus_repository.dart';

/// In-memory [AcademySyllabusRepository] (Phase 9 foundation scaffold,
/// Task 8.8).
///
/// Serves the canonical deterministic seed syllabus (shared with the
/// production local-cache repository via [AcademySeed]) so the Phase-9
/// entry points (masthead, syllabus list, progress) can render without a
/// database. The production implementation ([LocalAcademySyllabusRepository])
/// is local-cache-first over the encrypted SQLCipher database.
class InMemoryAcademySyllabusRepository implements AcademySyllabusRepository {
  final AcademySyllabus _syllabus;

  InMemoryAcademySyllabusRepository({AcademySyllabus? seed})
      : _syllabus = seed ?? AcademySeed.syllabus;

  /// The canonical scaffold syllabus: two domains, a handful of modules.
  /// Deterministic — same ids/titles on every invocation.
  static final AcademySyllabus seedSyllabus = AcademySeed.syllabus;

  @override
  Future<AcademySyllabus> fetchSyllabus() async => _syllabus;
}
