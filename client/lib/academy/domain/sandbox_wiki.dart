import 'dart:math';

import 'academy_module.dart';

/// A Sandbox Wiki page (Task 9.5 — community study notes for one module).
///
/// SECURITY CHECKPOINT (Task 9.5): the page carries ONLY a validated UUID
/// v4 [pageId], the parent module's UUID v4 id, a PUBLIC title, a locale
/// tag, a revision count and a timestamp — zero identity, zero phone, zero
/// handle, zero hash fields. The body lives in the revision history, never
/// on the page row.
class SandboxPage {
  /// The page's validated UUID v4 id.
  final String pageId;

  /// The parent module's validated UUID v4 id (the sandbox is
  /// module-scoped — DESIGN.md §9 module view).
  final String moduleId;

  /// Public page title (community content, not identity).
  final String title;

  /// ISO 639-1 locale tag (optionally with region).
  final String locale;

  /// Number of revisions in the version history (>= 1).
  final int revisionCount;

  /// Last revision timestamp (UTC).
  final DateTime updatedAt;

  const SandboxPage._({
    required this.pageId,
    required this.moduleId,
    required this.title,
    required this.locale,
    required this.revisionCount,
    required this.updatedAt,
  });

  /// Validates every field, returning a [SandboxPage] or null when
  /// malformed (bad UUID v4 ids / empty title / bad locale / count < 1).
  static SandboxPage? tryParse({
    required String pageId,
    required String moduleId,
    required String title,
    required String locale,
    required int revisionCount,
    required DateTime updatedAt,
  }) {
    if (!UuidV4.isValid(pageId) ||
        !UuidV4.isValid(moduleId) ||
        title.trim().isEmpty ||
        !LocaleTag.isValid(locale) ||
        revisionCount < 1) {
      return null;
    }
    return SandboxPage._(
      pageId: pageId,
      moduleId: moduleId,
      title: title.trim(),
      locale: locale,
      revisionCount: revisionCount,
      updatedAt: updatedAt,
    );
  }

  /// Parses via [tryParse], throwing [ArgumentError] on malformed input.
  static SandboxPage parse({
    required String pageId,
    required String moduleId,
    required String title,
    required String locale,
    required int revisionCount,
    required DateTime updatedAt,
  }) {
    final page = tryParse(
      pageId: pageId,
      moduleId: moduleId,
      title: title,
      locale: locale,
      revisionCount: revisionCount,
      updatedAt: updatedAt,
    );
    if (page == null) {
      throw ArgumentError('Invalid sandbox page (one or more fields '
          'malformed)');
    }
    return page;
  }

  @override
  bool operator ==(Object other) =>
      other is SandboxPage &&
      other.pageId == pageId &&
      other.moduleId == moduleId &&
      other.title == title &&
      other.locale == locale &&
      other.revisionCount == revisionCount &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(pageId, moduleId, title, locale, revisionCount, updatedAt);
}

/// A single Sandbox revision — the append-only version history
/// (PRD FR-A3: every revision is diffable and revertible, with
/// attributed-but-pseudonymous authorship).
///
/// SECURITY CHECKPOINT (Task 9.5): [authorHandle] is the derived
/// `SA-####` pseudonymous handle ([SandboxAuthorHandle]) — NEVER a name,
/// phone, email, blind hash or device id. [bodyMarkdown] is community
/// UGC persisted inside the encrypted partition (SQLCipher + flagged
/// sensitive; the sealed sync envelope carries it only as ciphertext).
class SandboxRevision {
  /// The revision's validated UUID v4 id (doubles as the sync
  /// idempotency key).
  final String revisionId;

  /// The parent page's validated UUID v4 id.
  final String pageId;

  /// The Markdown body at this revision (community UGC, encrypted at rest).
  final String bodyMarkdown;

  /// The deterministic pseudonymous author handle (`SA-####`).
  final String authorHandle;

  /// Revision timestamp (UTC).
  final DateTime createdAt;

  /// The revision id this one supersedes (null for the page's first).
  final String? prevRevisionId;

  const SandboxRevision._({
    required this.revisionId,
    required this.pageId,
    required this.bodyMarkdown,
    required this.authorHandle,
    required this.createdAt,
    this.prevRevisionId,
  });

  /// Validates every field, returning a [SandboxRevision] or null when
  /// malformed (bad UUID v4 ids / empty body / bad author handle).
  static SandboxRevision? tryParse({
    required String revisionId,
    required String pageId,
    required String bodyMarkdown,
    required String authorHandle,
    required DateTime createdAt,
    String? prevRevisionId,
  }) {
    if (!UuidV4.isValid(revisionId) ||
        !UuidV4.isValid(pageId) ||
        !SandboxAuthorHandle.isValid(authorHandle) ||
        (prevRevisionId != null && !UuidV4.isValid(prevRevisionId))) {
      return null;
    }
    return SandboxRevision._(
      revisionId: revisionId,
      pageId: pageId,
      bodyMarkdown: bodyMarkdown,
      authorHandle: authorHandle,
      createdAt: createdAt,
      prevRevisionId: prevRevisionId,
    );
  }

  /// Parses via [tryParse], throwing [ArgumentError] on malformed input.
  static SandboxRevision parse({
    required String revisionId,
    required String pageId,
    required String bodyMarkdown,
    required String authorHandle,
    required DateTime createdAt,
    String? prevRevisionId,
  }) {
    final revision = tryParse(
      revisionId: revisionId,
      pageId: pageId,
      bodyMarkdown: bodyMarkdown,
      authorHandle: authorHandle,
      createdAt: createdAt,
      prevRevisionId: prevRevisionId,
    );
    if (revision == null) {
      throw ArgumentError('Invalid sandbox revision (one or more fields '
          'malformed)');
    }
    return revision;
  }
}

/// Attributed-but-pseudonymous Sandbox authorship (PRD FR-A3).
///
/// Every revision is authored by a DETERMINISTIC per-module handle
/// (`SA-` + 4 hex chars from the module id, FNV-1a) — the same module
/// always yields the same handle, so a collaborator's contributions are
/// attributable across revisions WITHOUT any identity. Zero names, phones,
/// hashes or device ids can ever be an author handle.
abstract final class SandboxAuthorHandle {
  static final RegExp _pattern = RegExp(r'^SA-[0-9a-f]{4}$');

  static bool isValid(String raw) => _pattern.hasMatch(raw);

  /// The deterministic handle for [moduleId] (FNV-1a 32-bit → 4 hex).
  static String forModule(String moduleId) {
    var hash = 0x811c9dc5;
    for (final unit in moduleId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final suffix = (hash & 0xFFFF).toRadixString(16).padLeft(4, '0');
    return 'SA-$suffix';
  }
}

/// One line of a [SandboxLineDiff] result.
class SandboxDiffLine {
  /// The line index in the source (removed) or target (added) text.
  final int index;

  /// The line text (public community content, never identity).
  final String text;

  const SandboxDiffLine({required this.index, required this.text});

  @override
  bool operator ==(Object other) =>
      other is SandboxDiffLine && other.index == index && other.text == text;

  @override
  int get hashCode => Object.hash(index, text);
}

/// The deterministic result of diffing two Markdown bodies (PRD FR-A3 —
/// every revision is diffable). Carries only line entries + counts — a
/// non-PII summary safe for the UI and logs.
class SandboxDiffResult {
  /// Lines present in the new text but not the old (in new-text order).
  final List<SandboxDiffLine> added;

  /// Lines present in the old text but not the new (in old-text order).
  final List<SandboxDiffLine> removed;

  const SandboxDiffResult({required this.added, required this.removed});

  int get additions => added.length;
  int get removals => removed.length;

  /// UI label, e.g. `+3 −1` — public, non-PII.
  String get summary => '+$additions −$removals';

  bool get isClean => added.isEmpty && removed.isEmpty;
}

/// Pure deterministic line diff for Sandbox version control (Task 9.5).
///
/// Classic LCS backtrack — identical inputs ALWAYS produce the identical
/// result (no randomness, no clock). No content is ever logged or leaked;
/// callers render only the [SandboxDiffResult] summaries.
abstract final class SandboxLineDiff {
  /// Diffs [oldText] against [newText] line-by-line (split on `\n`).
  ///
  /// An EMPTY text has ZERO lines (not one empty line) — so diffing
  /// against `''` is a pure all-lines removal/addition and `diff('','')`
  /// is clean (deterministic, no trailing-newline artifacts).
  static SandboxDiffResult diff(String oldText, String newText) {
    final oldLines = oldText.isEmpty ? const <String>[] : oldText.split('\n');
    final newLines = newText.isEmpty ? const <String>[] : newText.split('\n');
    final n = oldLines.length;
    final m = newLines.length;

    // LCS table (bottom-up).
    final lcs = List.generate(n + 1, (_) => List.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        lcs[i][j] = oldLines[i] == newLines[j]
            ? lcs[i + 1][j + 1] + 1
            : max(lcs[i + 1][j], lcs[i][j + 1]);
      }
    }

    // Backtrack to collect additions/removals deterministically.
    final added = <SandboxDiffLine>[];
    final removed = <SandboxDiffLine>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (oldLines[i] == newLines[j]) {
        i++;
        j++;
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        removed.add(SandboxDiffLine(index: i, text: oldLines[i]));
        i++;
      } else {
        added.add(SandboxDiffLine(index: j, text: newLines[j]));
        j++;
      }
    }
    while (i < n) {
      removed.add(SandboxDiffLine(index: i, text: oldLines[i]));
      i++;
    }
    while (j < m) {
      added.add(SandboxDiffLine(index: j, text: newLines[j]));
      j++;
    }
    return SandboxDiffResult(added: added, removed: removed);
  }
}

/// Sandbox Wiki persistence boundary (port).
///
/// The production implementation is backed by the encrypted SQLCipher
/// database (`sandbox_pages` + `sandbox_revisions`, schema v12) and is
/// OFFLINE-FIRST: the local rows are written before anything else; the
/// sealed sync enqueue (QueueSandboxRevisionSink) wraps the same port.
/// All ids are validated UUID v4; author handles are `SA-####` only.
abstract class SandboxWikiRepository {
  /// Every page, newest-updated first (optionally scoped to [moduleId]).
  Future<List<SandboxPage>> listPages({String? moduleId});

  /// The page with [pageId], or null when absent.
  Future<SandboxPage?> getPage(String pageId);

  /// The page's revision history, oldest first.
  Future<List<SandboxRevision>> listRevisions(String pageId);

  /// Submits a Markdown revision.
  ///
  /// [pageId] null = create a NEW page (first revision); non-null = append
  /// a revision to the existing page (bumping its revision count and
  /// updating [title] if it changed). Returns the updated page.
  Future<SandboxPage> submitRevision({
    required String? pageId,
    required String moduleId,
    required String title,
    required String bodyMarkdown,
    required String locale,
    required String authorHandle,
  });

  /// Appends a NEW revision whose body equals [revisionId]'s (append-only
  /// revert — the history is never rewritten). Returns the updated page.
  /// Throws when [revisionId] is not in [pageId]'s history.
  Future<SandboxPage> revertToRevision({
    required String pageId,
    required String revisionId,
    required String authorHandle,
  });
}
