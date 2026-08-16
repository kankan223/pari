/// Academy syllabus value objects (Phase 9 foundation scaffold, Task 8.8).
///
/// The Academy (Pillar 4) is a structured syllabus — Domain → Category →
/// Subject → Module (MASTER_PLAN §9.2). This foundation defines the two
/// level types the Phase-9 entry points need up front: [AcademyDomain]
/// (the top of the tree) and [AcademyModule] (the leaf). Deeper levels
/// land with Task 9.2.
///
/// SECURITY CHECKPOINT (Phase 9): every Academy entity carries ZERO
/// identity — only a UUID module id, fixed locale tags, public course
/// titles and an opaque non-PII content reference. No phones, no names, no
/// emails, no 64-hex hashes, no device identifiers ever cross these models
/// (mirrors the zero-identity invariants of the Ledger and War Room).
class AcademyDomain {
  /// Stable domain identifier, e.g. `math` or `civics`.
  final String domainId;

  /// Public course-domain title (course content, not identity).
  final String title;

  /// ISO 639-1 language tag (optionally with region), e.g. `en` / `hi`.
  final String locale;

  const AcademyDomain._({
    required this.domainId,
    required this.title,
    required this.locale,
  });

  /// Validates [domainId], [title] and [locale], returning an
  /// [AcademyDomain] or null when malformed.
  static AcademyDomain? tryParse({
    required String domainId,
    required String title,
    required String locale,
  }) {
    if (domainId.trim().isEmpty ||
        title.trim().isEmpty ||
        !LocaleTag.isValid(locale)) {
      return null;
    }
    return AcademyDomain._(domainId: domainId, title: title, locale: locale);
  }

  /// Parses via [tryParse], throwing [ArgumentError] on malformed input.
  static AcademyDomain parse({
    required String domainId,
    required String title,
    required String locale,
  }) {
    final domain = tryParse(domainId: domainId, title: title, locale: locale);
    if (domain == null) {
      throw ArgumentError(
          'Invalid academy domain (domainId/title/locale malformed)');
    }
    return domain;
  }

  @override
  bool operator ==(Object other) =>
      other is AcademyDomain &&
      other.domainId == domainId &&
      other.title == title &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(domainId, title, locale);
}

/// A single Academy learning module (the leaf of the syllabus tree).
///
/// [contentRef] is an OPAQUE, non-PII reference to the module's media —
/// never a raw URL, never a filename that could leak identity. The video
/// delivery mapping lands with Task 9.3.
class AcademyModule {
  /// UUID v4 module identifier (validated, zero-PII).
  final String moduleId;

  /// Parent domain id ([AcademyDomain.domainId]).
  final String domainId;

  /// Public module title (course content, not identity).
  final String title;

  /// Nominal duration in minutes (>= 1).
  final int durationMinutes;

  /// ISO 639-1 language tag (optionally with region).
  final String locale;

  /// Opaque non-PII content reference for the module's media.
  final String contentRef;

  const AcademyModule._({
    required this.moduleId,
    required this.domainId,
    required this.title,
    required this.durationMinutes,
    required this.locale,
    required this.contentRef,
  });

  /// Validates every field, returning an [AcademyModule] or null when
  /// malformed (bad UUID v4 / empty ids/titles / duration < 1 / bad
  /// locale / empty content ref).
  static AcademyModule? tryParse({
    required String moduleId,
    required String domainId,
    required String title,
    required int durationMinutes,
    required String locale,
    required String contentRef,
  }) {
    if (!UuidV4.isValid(moduleId) ||
        domainId.trim().isEmpty ||
        title.trim().isEmpty ||
        durationMinutes < 1 ||
        !LocaleTag.isValid(locale) ||
        contentRef.trim().isEmpty) {
      return null;
    }
    return AcademyModule._(
      moduleId: moduleId,
      domainId: domainId,
      title: title,
      durationMinutes: durationMinutes,
      locale: locale,
      contentRef: contentRef,
    );
  }

  /// Parses via [tryParse], throwing [ArgumentError] on malformed input.
  static AcademyModule parse({
    required String moduleId,
    required String domainId,
    required String title,
    required int durationMinutes,
    required String locale,
    required String contentRef,
  }) {
    final module = tryParse(
      moduleId: moduleId,
      domainId: domainId,
      title: title,
      durationMinutes: durationMinutes,
      locale: locale,
      contentRef: contentRef,
    );
    if (module == null) {
      throw ArgumentError('Invalid academy module (one or more fields '
          'malformed)');
    }
    return module;
  }

  @override
  bool operator ==(Object other) =>
      other is AcademyModule &&
      other.moduleId == moduleId &&
      other.domainId == domainId &&
      other.title == title &&
      other.durationMinutes == durationMinutes &&
      other.locale == locale &&
      other.contentRef == contentRef;

  @override
  int get hashCode => Object.hash(
      moduleId, domainId, title, durationMinutes, locale, contentRef);
}

/// The full syllabus: the domain list plus the module list, with tree
/// helpers. Offline-first: the repository serves a LOCAL snapshot.
class AcademySyllabus {
  final List<AcademyDomain> domains;
  final List<AcademyModule> modules;

  const AcademySyllabus({required this.domains, required this.modules});

  int get moduleCount => modules.length;

  /// Modules belonging to [domainId], in syllabus order.
  List<AcademyModule> modulesFor(String domainId) =>
      modules.where((m) => m.domainId == domainId).toList(growable: false);
}

/// Strict UUID v4 shape (RFC 4122, version 4, RFC variant bits).
abstract final class UuidV4 {
  static final RegExp _pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static bool isValid(String raw) => _pattern.hasMatch(raw.toLowerCase());
}

/// ISO 639-1 locale tag, optionally with a two-letter region suffix.
abstract final class LocaleTag {
  static final RegExp _pattern = RegExp(r'^[a-z]{2}(-[A-Z]{2})?$');

  static bool isValid(String raw) => _pattern.hasMatch(raw);
}
