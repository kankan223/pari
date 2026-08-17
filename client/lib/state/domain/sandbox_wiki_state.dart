import '../../academy/domain/sandbox_wiki.dart';

/// Lifecycle of the Sandbox Wiki view (Task 9.5).
enum SandboxWikiPhase {
  /// No load attempted yet.
  idle,

  /// Loading the local wiki snapshot.
  loading,

  /// The wiki is available and the UI can render.
  ready,

  /// The wiki could not be loaded — generic error state.
  failure,
}

/// Immutable BLoC state for the Sandbox Wiki (Task 9.5).
///
/// SECURITY CHECKPOINT (Task 9.5): the state carries ONLY module-scoped
/// wiki pages + revisions (UUID v4 ids, public titles, `SA-####` author
/// handles, timestamps, diff summaries) — never identity, never PII.
/// [errorMessage] is always the SAME generic string (no side channel).
class SandboxWikiState {
  final SandboxWikiPhase phase;

  /// The module scope (validated UUID v4 — the sandbox is module-scoped).
  final String moduleId;

  /// Every page in the scope, newest-updated first.
  final List<SandboxPage> pages;

  /// The live title search/filter query.
  final String query;

  /// [pages] filtered by [query] (case-insensitive title substring).
  final List<SandboxPage> filteredPages;

  /// The open page (null until one is selected).
  final SandboxPage? selectedPage;

  /// The selected page's revision history, oldest first.
  final List<SandboxRevision> revisions;

  /// The edit draft body (in-memory; persisted only on submit).
  final String draftBody;

  /// Generic failure message — constant, never content-specific.
  final String errorMessage;

  const SandboxWikiState({
    this.phase = SandboxWikiPhase.idle,
    this.moduleId = '',
    this.pages = const [],
    this.query = '',
    this.filteredPages = const [],
    this.selectedPage,
    this.revisions = const [],
    this.draftBody = '',
    this.errorMessage = '',
  });

  bool get isReady => phase == SandboxWikiPhase.ready;

  /// The deterministic pseudonymous author handle for the scope.
  String get authorHandle =>
      moduleId.isEmpty ? '' : SandboxAuthorHandle.forModule(moduleId);

  SandboxWikiState copyWith({
    SandboxWikiPhase? phase,
    String? moduleId,
    List<SandboxPage>? pages,
    String? query,
    List<SandboxPage>? filteredPages,
    SandboxPage? selectedPage,
    bool clearSelectedPage = false,
    List<SandboxRevision>? revisions,
    String? draftBody,
    String? errorMessage,
  }) =>
      SandboxWikiState(
        phase: phase ?? this.phase,
        moduleId: moduleId ?? this.moduleId,
        pages: pages ?? this.pages,
        query: query ?? this.query,
        filteredPages: filteredPages ?? this.filteredPages,
        selectedPage:
            clearSelectedPage ? null : (selectedPage ?? this.selectedPage),
        revisions: revisions ?? this.revisions,
        draftBody: draftBody ?? this.draftBody,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}
