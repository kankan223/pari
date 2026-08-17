import 'dart:async';

import '../../academy/domain/sandbox_wiki.dart';
import '../domain/sandbox_wiki_bloc.dart';
import '../domain/sandbox_wiki_state.dart';

/// Local [SandboxWikiBloc] (data layer, Task 9.5).
///
/// Loads the module-scoped wiki snapshot from the local [SandboxWikiRepository]
/// port (offline-first — always the encrypted local store) and drives
/// browsing / search / page-open / draft / submit / revert through it.
/// Every mutation re-reads the local snapshot so the UI reflects the
/// persisted state immediately.
class LocalSandboxWikiBloc implements SandboxWikiBloc {
  static const String _genericError =
      'Unable to load the sandbox wiki. Please try again.';

  final SandboxWikiRepository _repository;

  final StreamController<SandboxWikiState> _controller =
      StreamController<SandboxWikiState>.broadcast();

  SandboxWikiState _current = const SandboxWikiState();

  /// Monotonic sequence — a stale load can never overwrite a fresher one
  /// (codebase convention).
  int _seq = 0;

  LocalSandboxWikiBloc({required SandboxWikiRepository repository})
      : _repository = repository;

  @override
  Stream<SandboxWikiState> get state => _controller.stream;

  /// The latest emitted state (non-stream read for navigation wiring).
  @override
  SandboxWikiState get current => _current;

  @override
  Future<void> start(String moduleId) async {
    _current =
        SandboxWikiState(phase: SandboxWikiPhase.loading, moduleId: moduleId);
    _controller.add(_current);
    await _load();
  }

  @override
  Future<void> retry() async {
    _current = _current.copyWith(phase: SandboxWikiPhase.loading);
    _controller.add(_current);
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    try {
      final pages = await _repository.listPages(moduleId: _current.moduleId);
      if (seq != _seq) {
        return; // stale load — a newer call superseded us.
      }
      _current = _current.copyWith(
        phase: SandboxWikiPhase.ready,
        pages: pages,
        filteredPages: _applyQuery(pages, _current.query),
      );
    } catch (_) {
      if (seq != _seq) {
        return;
      }
      _current = _current.copyWith(
        phase: SandboxWikiPhase.failure,
        errorMessage: _genericError,
      );
    }
    _controller.add(_current);
  }

  @override
  void search(String query) {
    _current = _current.copyWith(
      query: query,
      filteredPages: _applyQuery(_current.pages, query),
    );
    _controller.add(_current);
  }

  static List<SandboxPage> _applyQuery(List<SandboxPage> pages, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return pages;
    }
    return pages
        .where((p) => p.title.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Future<void> openPage(String pageId) async {
    final seq = ++_seq;
    try {
      final page = await _repository.getPage(pageId);
      final revisions = page == null
          ? const <SandboxRevision>[]
          : await _repository.listRevisions(pageId);
      if (seq != _seq) {
        return; // stale — a newer navigation superseded us.
      }
      _current = _current.copyWith(
        selectedPage: page,
        revisions: revisions,
      );
    } catch (_) {
      if (seq != _seq) {
        return;
      }
      _current = _current.copyWith(
        phase: SandboxWikiPhase.failure,
        errorMessage: _genericError,
      );
    }
    _controller.add(_current);
  }

  @override
  void setDraft(String body) {
    _current = _current.copyWith(draftBody: body);
    _controller.add(_current);
  }

  @override
  Future<void> submitDraft({required String title}) async {
    try {
      final page = await _repository.submitRevision(
        pageId: _current.selectedPage?.pageId,
        moduleId: _current.moduleId,
        title: title,
        bodyMarkdown: _current.draftBody,
        locale: 'en',
        authorHandle: _current.authorHandle,
      );
      _current = _current.copyWith(
        selectedPage: page,
        draftBody: '', // the draft is consumed by the submit
      );
    } catch (_) {
      // Graceful degradation — the generic failure state; the draft is
      // preserved so the user can retry.
      _current = _current.copyWith(
        phase: SandboxWikiPhase.failure,
        errorMessage: _genericError,
      );
    }
    await _load(); // refresh the page list.
    // Refresh the open page's revision history so the UI immediately
    // reflects the appended revision (the detail screen renders the
    // history from state, not from the repository).
    final selected = _current.selectedPage?.pageId;
    if (selected != null) {
      await openPage(selected);
    }
  }

  @override
  Future<void> revertTo(String revisionId) async {
    final pageId = _current.selectedPage?.pageId;
    if (pageId == null) {
      return;
    }
    try {
      await _repository.revertToRevision(
        pageId: pageId,
        revisionId: revisionId,
        authorHandle: _current.authorHandle,
      );
    } catch (_) {
      _current = _current.copyWith(
        phase: SandboxWikiPhase.failure,
        errorMessage: _genericError,
      );
    }
    await openPage(pageId); // reload the page + its new revision history.
  }

  @override
  Future<void> close() => _controller.close();
}
