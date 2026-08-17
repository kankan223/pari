import '../../repository/domain/entity_store.dart';
import '../domain/academy_module.dart';
import '../domain/academy_syllabus_repository.dart';

/// Production [AcademySyllabusRepository] (Task 9.2 Syllabus Tree).
///
/// Local-cache-first, exactly like the Ledger feed: the syllabus tree
/// (domains + modules) is served from the encrypted SQLCipher database —
/// the Academy NEVER blocks on the network. On first run the stores are
/// empty and the bundled deterministic seed syllabus is written to the
/// local cache; every subsequent load serves the cached snapshot.
///
/// SECURITY CHECKPOINT (Task 9.2): the cached syllabus is PUBLIC course
/// content — domain/module titles, UUID v4 module ids, locale tags,
/// durations, and OPAQUE non-PII content refs. Zero identity columns exist
/// in the academy tables (schema v10); this repository writes and reads
/// only those values.
class LocalAcademySyllabusRepository implements AcademySyllabusRepository {
  final EntityStore<AcademyDomain> _domainStore;
  final EntityStore<AcademyModule> _moduleStore;

  /// The bundled seed syllabus written on first run (local cache).
  final AcademySyllabus _seed;

  /// True once the local cache has been checked/seeded — the empty-check
  /// is only paid once per process.
  bool _seeded = false;

  LocalAcademySyllabusRepository({
    required EntityStore<AcademyDomain> domainStore,
    required EntityStore<AcademyModule> moduleStore,
    AcademySyllabus? seed,
  })  : _domainStore = domainStore,
        _moduleStore = moduleStore,
        _seed = seed ?? AcademySeed.syllabus;

  @override
  Future<AcademySyllabus> fetchSyllabus() async {
    await _ensureSeeded();
    final domains = await _domainStore.getAll();
    final modules = await _moduleStore.getAll();
    // Deterministic ordering: modules keep their seed/insertion order
    // (SQLCipher EntityStore returns rows in insertion order), grouped by
    // the domain list. The syllabus shape is re-validated on read through
    // AcademySyllabus construction.
    return AcademySyllabus(domains: domains, modules: modules);
  }

  /// Writes the bundled seed into the empty local cache (idempotent).
  Future<void> _ensureSeeded() async {
    if (_seeded) {
      return;
    }
    _seeded = true;
    final domains = await _domainStore.getAll();
    final modules = await _moduleStore.getAll();
    if (domains.isNotEmpty || modules.isNotEmpty) {
      return; // cache already populated — never overwrite local data.
    }
    for (final d in _seed.domains) {
      await _domainStore.insert(d);
    }
    for (final m in _seed.modules) {
      await _moduleStore.insert(m);
    }
  }
}

/// The canonical bundled syllabus seed (shared by the in-memory scaffold
/// repository and the production local-cache-first repository so the app
/// and its tests see identical content).
abstract final class AcademySeed {
  static final AcademySyllabus syllabus = AcademySyllabus(
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
}
