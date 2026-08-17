import 'sandbox_wiki_state.dart';

/// BLoC for the Sandbox Wiki (Task 9.5).
///
/// Loads the module-scoped wiki snapshot through the
/// [SandboxWikiRepository] port (offline-first — always the local encrypted
/// store) and drives browsing, title search/filtering, page opening, the
/// Markdown edit draft and revision submission/revert. The UI binds to
/// [state] and never touches the repository directly.
///
/// SECURITY CHECKPOINT (Task 9.5): state carries only module-scoped pages +
/// revisions (UUID ids, public titles, `SA-####` handles, timestamps) —
/// never identity, never PII.
abstract class SandboxWikiBloc {
  /// Stream of wiki states.
  Stream<SandboxWikiState> get state;

  /// The latest emitted state (non-stream read for navigation wiring).
  SandboxWikiState get current;

  /// Loads the wiki snapshot for [moduleId].
  Future<void> start(String moduleId);

  /// Retries loading after a failure.
  Future<void> retry();

  /// Filters the page list by [query] (case-insensitive title substring).
  void search(String query);

  /// Opens [pageId] and loads its revision history.
  Future<void> openPage(String pageId);

  /// Sets the in-memory edit draft [body].
  void setDraft(String body);

  /// Submits [title] + the current [draftBody] as a revision (creates the
  /// page when none is open). Clears the draft on success.
  Future<void> submitDraft({required String title});

  /// Reverts the open page to [revisionId] (append-only revert).
  Future<void> revertTo(String revisionId);

  /// Releases resources.
  Future<void> close();
}
