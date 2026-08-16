import '../domain/academy_module.dart';
import '../domain/academy_syllabus_repository.dart';

/// In-memory [AcademySyllabusRepository] (Phase 9 foundation scaffold,
/// Task 8.8).
///
/// Serves a small deterministic seed syllabus so the Phase-9 entry points
/// (masthead, syllabus list, progress) can render before the production
/// local-cache repository lands. The production implementation will be
/// local-cache-first exactly like the Ledger feed.
class InMemoryAcademySyllabusRepository implements AcademySyllabusRepository {
  final AcademySyllabus _syllabus;

  InMemoryAcademySyllabusRepository({AcademySyllabus? seed})
      : _syllabus = seed ?? seedSyllabus;

  /// The canonical scaffold syllabus: two domains, a handful of modules.
  /// Deterministic — same ids/titles on every invocation.
  static final AcademySyllabus seedSyllabus = AcademySyllabus(
    domains: [
      AcademyDomain.parse(
          domainId: 'civics', title: 'Civic Education', locale: 'en'),
      AcademyDomain.parse(domainId: 'tech', title: 'Technology', locale: 'en'),
    ],
    modules: [
      AcademyModule.parse(
        moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
        domainId: 'civics',
        title: 'Fundamentals of Civic Rights',
        durationMinutes: 18,
        locale: 'en',
        contentRef: 'civics/rights-fundamentals/mod-01',
      ),
      AcademyModule.parse(
        moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
        domainId: 'civics',
        title: 'Reporting & Evidence Basics',
        durationMinutes: 24,
        locale: 'en',
        contentRef: 'civics/reporting-basics/mod-02',
      ),
      AcademyModule.parse(
        moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3303',
        domainId: 'tech',
        title: 'Privacy-First Phone Setup',
        durationMinutes: 15,
        locale: 'en',
        contentRef: 'tech/privacy-phone/mod-03',
      ),
    ],
  );

  @override
  Future<AcademySyllabus> fetchSyllabus() async => _syllabus;
}
