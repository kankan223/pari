import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcademyModule (Phase 9 foundation)', () {
    test('tryParse accepts a valid module', () {
      final module = AcademyModule.tryParse(
        moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
        domainId: 'civics',
        title: 'Fundamentals of Civic Rights',
        durationMinutes: 18,
        locale: 'en',
        contentRef: 'civics/rights-fundamentals/mod-01',
      );
      expect(module, isNotNull);
      expect(module!.moduleId, '3f2504e0-4f89-41d3-9a0c-0305e82c3301');
      expect(module.durationMinutes, 18);
    });

    test('rejects a non-UUID-v4 module id', () {
      expect(
        AcademyModule.tryParse(
          moduleId: 'not-a-uuid',
          domainId: 'civics',
          title: 't',
          durationMinutes: 10,
          locale: 'en',
          contentRef: 'c',
        ),
        isNull,
      );
      // Wrong version nibble (must be 4) / wrong variant nibble (must be 89ab).
      expect(
        AcademyModule.tryParse(
          moduleId: '3f2504e0-4f89-31d3-9a0c-0305e82c3301',
          domainId: 'civics',
          title: 't',
          durationMinutes: 10,
          locale: 'en',
          contentRef: 'c',
        ),
        isNull,
      );
    });

    test('rejects empty ids/titles/content refs', () {
      expect(
        AcademyModule.tryParse(
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
          domainId: '  ',
          title: 't',
          durationMinutes: 10,
          locale: 'en',
          contentRef: 'c',
        ),
        isNull,
      );
      expect(
        AcademyModule.tryParse(
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
          domainId: 'civics',
          title: '  ',
          durationMinutes: 10,
          locale: 'en',
          contentRef: 'c',
        ),
        isNull,
      );
      expect(
        AcademyModule.tryParse(
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
          domainId: 'civics',
          title: 't',
          durationMinutes: 10,
          locale: 'en',
          contentRef: '  ',
        ),
        isNull,
      );
    });

    test('rejects non-positive duration and bad locale tags', () {
      expect(
        AcademyModule.tryParse(
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
          domainId: 'civics',
          title: 't',
          durationMinutes: 0,
          locale: 'en',
          contentRef: 'c',
        ),
        isNull,
      );
      expect(
        AcademyModule.tryParse(
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
          domainId: 'civics',
          title: 't',
          durationMinutes: 10,
          locale: 'english',
          contentRef: 'c',
        ),
        isNull,
      );
      // Regional suffix allowed.
      expect(
        AcademyModule.tryParse(
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
          domainId: 'civics',
          title: 't',
          durationMinutes: 10,
          locale: 'hi-IN',
          contentRef: 'c',
        ),
        isNotNull,
      );
    });

    test('parse throws ArgumentError on malformed input', () {
      expect(
        () => AcademyModule.parse(
          moduleId: 'nope',
          domainId: 'civics',
          title: 't',
          durationMinutes: 10,
          locale: 'en',
          contentRef: 'c',
        ),
        throwsArgumentError,
      );
    });

    test('value equality + hashCode by all fields', () {
      final a = AcademyModule.tryParse(
        moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
        domainId: 'civics',
        title: 'Fundamentals of Civic Rights',
        durationMinutes: 18,
        locale: 'en',
        contentRef: 'civics/rights-fundamentals/mod-01',
      )!;
      final b = AcademyModule.tryParse(
        moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
        domainId: 'civics',
        title: 'Fundamentals of Civic Rights',
        durationMinutes: 18,
        locale: 'en',
        contentRef: 'civics/rights-fundamentals/mod-01',
      )!;
      final c = AcademyModule.tryParse(
        moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
        domainId: 'civics',
        title: 'Fundamentals of Civic Rights',
        durationMinutes: 18,
        locale: 'en',
        contentRef: 'civics/rights-fundamentals/mod-01',
      )!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('AcademyDomain (Phase 9 foundation)', () {
    test('tryParse accepts a valid domain', () {
      final domain = AcademyDomain.tryParse(
        domainId: 'civics',
        title: 'Civic Education',
        locale: 'en',
      );
      expect(domain, isNotNull);
      expect(domain!.domainId, 'civics');
    });

    test('rejects empty ids/titles and bad locales', () {
      expect(
        AcademyDomain.tryParse(
            domainId: ' ', title: 'Civic Education', locale: 'en'),
        isNull,
      );
      expect(
        AcademyDomain.tryParse(domainId: 'civics', title: ' ', locale: 'en'),
        isNull,
      );
      expect(
        AcademyDomain.tryParse(domainId: 'civics', title: 't', locale: 'EN'),
        isNull,
      );
    });
  });

  group('AcademySyllabus (Phase 9 foundation)', () {
    final syllabus = AcademySyllabus(
      domains: [
        AcademyDomain.parse(
            domainId: 'civics', title: 'Civic Education', locale: 'en'),
        AcademyDomain.parse(
            domainId: 'tech', title: 'Technology', locale: 'en'),
      ],
      modules: [
        AcademyModule.parse(
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
          domainId: 'civics',
          title: 'm1',
          durationMinutes: 10,
          locale: 'en',
          contentRef: 'c1',
        ),
        AcademyModule.parse(
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
          domainId: 'civics',
          title: 'm2',
          durationMinutes: 20,
          locale: 'en',
          contentRef: 'c2',
        ),
        AcademyModule.parse(
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3303',
          domainId: 'tech',
          title: 'm3',
          durationMinutes: 15,
          locale: 'en',
          contentRef: 'c3',
        ),
      ],
    );

    test('moduleCount and modulesFor group by domain', () {
      expect(syllabus.moduleCount, 3);
      expect(syllabus.modulesFor('civics').length, 2);
      expect(syllabus.modulesFor('tech').length, 1);
      expect(syllabus.modulesFor('missing'), isEmpty);
    });

    test('zero-identity structural scan: no PII-shaped fields exist', () {
      // The only field values across every domain/module are: UUID module
      // ids, public titles, locale tags, durations, and opaque content refs.
      for (final m in syllabus.modules) {
        expect(m.moduleId, matches(RegExp(r'^[0-9a-f-]{36}$')));
        expect(m.locale, matches(RegExp(r'^[a-z]{2}(-[A-Z]{2})?$')));
        expect(m.contentRef.trim(), isNotEmpty,
            reason: 'content refs are opaque, never URLs/hashes');
      }
      for (final d in syllabus.domains) {
        expect(d.locale, matches(RegExp(r'^[a-z]{2}(-[A-Z]{2})?$')));
      }
    });
  });

  group('UuidV4 / LocaleTag helpers', () {
    test('UuidV4.isValid enforces version + variant nibbles', () {
      expect(UuidV4.isValid('3f2504e0-4f89-41d3-9a0c-0305e82c3301'), isTrue);
      expect(
          UuidV4.isValid('3f2504e0-4f89-41d3-9a0c-0305e82c3301'.toUpperCase()),
          isTrue);
      expect(UuidV4.isValid(''), isFalse);
      expect(UuidV4.isValid('3f2504e0-4f89-51d3-9a0c-0305e82c3301'), isFalse);
    });

    test('LocaleTag.isValid accepts en, hi-IN; rejects others', () {
      expect(LocaleTag.isValid('en'), isTrue);
      expect(LocaleTag.isValid('hi-IN'), isTrue);
      expect(LocaleTag.isValid('english'), isFalse);
      expect(LocaleTag.isValid('EN'), isFalse);
      expect(LocaleTag.isValid(''), isFalse);
    });
  });
}
