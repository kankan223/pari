import 'package:civic_commons/academy/data/local_academy_progress_store.dart';
import 'package:civic_commons/academy/data/local_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:civic_commons/academy/domain/academy_progress_record.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

/// Shared module ids from the canonical seed.
const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const _m2 = '3f2504e0-4f89-41d3-9a0c-0305e82c3302';
const _m3 = '3f2504e0-4f89-41d3-9a0c-0305e82c3303';

void main() {
  group('LocalAcademySyllabusRepository (Task 9.2 — local cache)', () {
    test('seeds the empty local cache and serves the syllabus', () async {
      final repo = LocalAcademySyllabusRepository(
        domainStore: InMemoryEntityStore<AcademyDomain>((d) => d.domainId),
        moduleStore: InMemoryEntityStore<AcademyModule>((m) => m.moduleId),
      );

      final syllabus = await repo.fetchSyllabus();

      expect(syllabus.domains, hasLength(2));
      expect(syllabus.modules, hasLength(3));
      expect(syllabus.modulesFor('civics'), hasLength(2));
      expect(syllabus.modulesFor('tech'), hasLength(1));
    });

    test('is local-cache-first: a second load reads the cache, not the seed',
        () async {
      final domainStore = InMemoryEntityStore<AcademyDomain>((d) => d.domainId);
      final moduleStore = InMemoryEntityStore<AcademyModule>((m) => m.moduleId);
      final repo = LocalAcademySyllabusRepository(
        domainStore: domainStore,
        moduleStore: moduleStore,
      );

      await repo.fetchSyllabus(); // seeds
      final before = moduleStore.length;

      // Mutate the cache directly, then confirm a fresh load serves the
      // CACHE (never re-seeds/overwrites local data).
      await moduleStore.delete(_m3);
      final syllabus = await repo.fetchSyllabus();
      expect(syllabus.modules, hasLength(2));
      expect(moduleStore.length, before - 1);
    });

    test('never overwrites a pre-populated cache', () async {
      final domainStore = InMemoryEntityStore<AcademyDomain>((d) => d.domainId);
      final moduleStore = InMemoryEntityStore<AcademyModule>((m) => m.moduleId);
      // A cache pre-populated with ONLY one domain/module (partial sync).
      await domainStore.insert(AcademyDomain.parse(
          domainId: 'custom', title: 'Custom', locale: 'en'));
      await moduleStore.insert(AcademyModule.parse(
        moduleId: _m1,
        domainId: 'custom',
        title: 'custom module',
        durationMinutes: 5,
        locale: 'en',
        contentRef: 'custom/only',
      ));

      final repo = LocalAcademySyllabusRepository(
        domainStore: domainStore,
        moduleStore: moduleStore,
      );
      final syllabus = await repo.fetchSyllabus();

      expect(syllabus.domains, hasLength(1));
      expect(syllabus.domains.single.domainId, 'custom');
      expect(syllabus.modules.single.title, 'custom module');
    });

    test('supports an injected seed (test seam)', () async {
      final custom = AcademySyllabus(
        domains: [
          AcademyDomain.parse(
              domainId: 'math', title: 'Mathematics', locale: 'en'),
        ],
        modules: [
          AcademyModule.parse(
            moduleId: _m1,
            domainId: 'math',
            title: 'only module',
            durationMinutes: 5,
            locale: 'en',
            contentRef: 'math/only',
          ),
        ],
      );
      final repo = LocalAcademySyllabusRepository(
        domainStore: InMemoryEntityStore<AcademyDomain>((d) => d.domainId),
        moduleStore: InMemoryEntityStore<AcademyModule>((m) => m.moduleId),
        seed: custom,
      );

      final syllabus = await repo.fetchSyllabus();
      expect(syllabus.moduleCount, 1);
      expect(syllabus.domains.single.title, 'Mathematics');
    });

    test('deterministic across restarts — same ids/titles/ordering', () async {
      final domainStore = InMemoryEntityStore<AcademyDomain>((d) => d.domainId);
      final moduleStore = InMemoryEntityStore<AcademyModule>((m) => m.moduleId);
      final repo = LocalAcademySyllabusRepository(
        domainStore: domainStore,
        moduleStore: moduleStore,
      );
      final a = await repo.fetchSyllabus();

      // A fresh repository over the SAME backing stores (cold restart)
      // serves byte-identical content.
      final repoB = LocalAcademySyllabusRepository(
        domainStore: domainStore,
        moduleStore: moduleStore,
      );
      final b = await repoB.fetchSyllabus();

      expect(a.domains.map((d) => d.domainId).toList(),
          b.domains.map((d) => d.domainId).toList());
      expect(a.modules.map((m) => m.moduleId).toList(),
          b.modules.map((m) => m.moduleId).toList());
    });

    test(
        'row codecs round-trip and re-validate through parse (corrupt row '
        'rejected at read time)', () async {
      // The production read path re-validates every cached row: a forged
      // module row that is not a UUID v4 is rejected by AcademyModule.parse
      // (the same guard that keeps progress keys zero-identity).
      final domain = AcademyDomain.parse(
          domainId: 'civics', title: 'Civic Education', locale: 'en');
      final module = AcademyModule.parse(
        moduleId: _m1,
        domainId: 'civics',
        title: 'Fundamentals of Civic Rights',
        durationMinutes: 18,
        locale: 'en',
        contentRef: 'civics/rights-fundamentals/mod-01',
      );

      // Round-trip: entity → row → entity is lossless.
      expect(academyDomainFromRow(academyDomainToRow(domain)), domain);
      expect(academyModuleFromRow(academyModuleToRow(module)), module);
      final record = academyProgressRecordFromRow(academyProgressRecordToRow(
        const AcademyProgressRecord(moduleId: _m1),
      ));
      expect(record.moduleId, _m1);

      // Re-validation: a forged non-UUID module id is rejected at read time.
      final corrupt = Map<String, Object?>.from(academyModuleToRow(module))
        ..['module_id'] = 'not-a-uuid';
      expect(() => academyModuleFromRow(corrupt), throwsArgumentError);
    });

    test('SECURITY: the repository API takes no identity inputs', () async {
      // Compiler-enforced zero-PII: the only entity types are AcademyDomain
      // and AcademyModule — public course content. Nothing identity-typed
      // can even be expressed.
      final repo = LocalAcademySyllabusRepository(
        domainStore: InMemoryEntityStore<AcademyDomain>((d) => d.domainId),
        moduleStore: InMemoryEntityStore<AcademyModule>((m) => m.moduleId),
      );
      final syllabus = await repo.fetchSyllabus();
      for (final m in syllabus.modules) {
        expect(m.moduleId, matches(RegExp(r'^[0-9a-f-]{36}$')));
        expect(m.contentRef.trim(), isNotEmpty,
            reason: 'content refs are opaque, never URLs/hashes');
      }
    });
  });

  group('LocalAcademyProgressStore (Task 9.2 — encrypted local progress)', () {
    test('round-trips completed module ids', () async {
      final store = LocalAcademyProgressStore(
        store: InMemoryEntityStore<AcademyProgressRecord>((r) => r.moduleId),
      );
      expect(await store.loadCompletedModuleIds(), isEmpty);

      await store.markModuleComplete(_m1);
      await store.markModuleComplete(_m2);
      final completed = await store.loadCompletedModuleIds();
      expect(completed, hasLength(2));
      expect(completed, containsAll([_m1, _m2]));
    });

    test('markModuleComplete is idempotent', () async {
      final store = LocalAcademyProgressStore(
        store: InMemoryEntityStore<AcademyProgressRecord>((r) => r.moduleId),
      );
      await store.markModuleComplete(_m1);
      await store.markModuleComplete(_m1);
      expect(await store.loadCompletedModuleIds(), hasLength(1));
    });

    test('markModuleIncomplete removes and is idempotent', () async {
      final store = LocalAcademyProgressStore(
        store: InMemoryEntityStore<AcademyProgressRecord>((r) => r.moduleId),
      );
      await store.markModuleComplete(_m1);
      await store.markModuleIncomplete(_m1);
      await store.markModuleIncomplete(_m1); // absent row — no-op
      expect(await store.loadCompletedModuleIds(), isEmpty);
    });

    test('progress survives a cold restart through the backing store',
        () async {
      // Simulate a process restart: the same backing store rows are served
      // by a FRESH LocalAcademyProgressStore instance.
      final backing =
          InMemoryEntityStore<AcademyProgressRecord>((r) => r.moduleId);
      await LocalAcademyProgressStore(store: backing).markModuleComplete(_m1);
      await LocalAcademyProgressStore(store: backing).markModuleComplete(_m3);

      final afterRestart = LocalAcademyProgressStore(store: backing);
      final completed = await afterRestart.loadCompletedModuleIds();
      expect(completed, containsAll([_m1, _m3]));
      expect(completed, isNot(contains(_m2)));
    });

    test('SECURITY: progress keys are UUID module ids only (structural)',
        () async {
      // The store row type declares a single UUID module id — no identity
      // field can even be expressed; presence = completed.
      final store = LocalAcademyProgressStore(
        store: InMemoryEntityStore<AcademyProgressRecord>((r) => r.moduleId),
      );
      await store.markModuleComplete(_m1);
      final rows = await store.loadCompletedModuleIds();
      for (final id in rows) {
        expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      }
    });
  });
}
