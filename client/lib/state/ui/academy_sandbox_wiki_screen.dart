import 'package:flutter/material.dart';

import '../../academy/domain/academy_module.dart';
import '../../academy/domain/sandbox_wiki.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/sandbox_wiki_bloc.dart';
import '../domain/sandbox_wiki_state.dart';
import 'academy_sandbox_edit_screen.dart';
import 'academy_sandbox_page_screen.dart';
import 'academy_sandbox_wiki_format.dart';
import 'academy_theme.dart';

/// The Sandbox Wiki browse screen (Task 9.5 — community study notes for one
/// module).
///
/// Module-scoped page list with live title search/filter + the NEW PAGE
/// entry. Tapping a page opens its detail (body + revision history +
/// revert); NEW PAGE opens the Markdown editor.
///
/// SECURITY CHECKPOINT (Task 9.5): the screen renders ONLY public page
/// titles, revision counts, timestamps and the deterministic `SA-####`
/// author handle — no identity, no PII, no body previews in the list. All
/// state flows through the injected [SandboxWikiBloc]. Wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE) with the standard test seam.
class AcademySandboxWikiScreen extends StatefulWidget {
  final SandboxWikiBloc bloc;
  final AcademyModule module;

  /// Injectable FLAG_SECURE service (test seam) — null uses production.
  final SecureFlagService? secureFlagService;

  const AcademySandboxWikiScreen({
    super.key,
    required this.bloc,
    required this.module,
    this.secureFlagService,
  });

  @override
  State<AcademySandboxWikiScreen> createState() =>
      _AcademySandboxWikiScreenState();
}

class _AcademySandboxWikiScreenState extends State<AcademySandboxWikiScreen> {
  @override
  void initState() {
    super.initState();
    widget.bloc.start(widget.module.moduleId);
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AcademyTheme.paper,
      appBar: AppBar(
        backgroundColor: AcademyTheme.paper,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to module',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          '❧ THE ACADEMY',
          style: TextStyle(
            color: AcademyTheme.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: AcademyTheme.serifFont,
            letterSpacing: 1.1,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'SANDBOX',
                style: TextStyle(
                  color: AcademyTheme.emerald,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: AcademyTheme.monoFont,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _secure(
        StreamBuilder<SandboxWikiState>(
          stream: widget.bloc.state,
          builder: (context, snapshot) {
            // Late-subscribe fallback (broadcast stream does not replay).
            final state = snapshot.data ?? widget.bloc.current;
            if (state.phase == SandboxWikiPhase.failure) {
              return _FailureView(
                onRetry: () => widget.bloc.retry(),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    '${widget.module.title} › SANDBOX WIKI',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AcademyTheme.muted,
                      fontFamily: AcademyTheme.monoFont,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Community study notes · by ${state.authorHandle}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AcademyTheme.muted,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: TextField(
                    onChanged: widget.bloc.search,
                    style:
                        const TextStyle(fontSize: 13, color: AcademyTheme.ink),
                    decoration: InputDecoration(
                      hintText: 'Search pages…',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AcademyTheme.muted),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 18, color: AcademyTheme.muted),
                      isDense: true,
                      filled: true,
                      fillColor: AcademyTheme.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: const BorderSide(color: AcademyTheme.rule),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: const BorderSide(color: AcademyTheme.rule),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: state.filteredPages.isEmpty
                      ? _EmptyWiki(
                          hasQuery: state.query.trim().isNotEmpty,
                          onCreate: () => _openEdit(context, null),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                          itemCount: state.filteredPages.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) =>
                              _pageCard(context, state.filteredPages[index]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pageCard(BuildContext context, SandboxPage page) {
    return InkWell(
      onTap: () => _openPage(context, page),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AcademyTheme.surface,
          border: Border.all(color: AcademyTheme.rule),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            const Icon(Icons.menu_book_rounded,
                size: 16, color: AcademyTheme.emerald),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AcademyTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${page.revisionCount} revision'
                    '${page.revisionCount == 1 ? '' : 's'} · '
                    '${sandboxTimeLabel(page.updatedAt)}',
                    style: const TextStyle(
                        fontSize: 11, color: AcademyTheme.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AcademyTheme.muted),
          ],
        ),
      ),
    );
  }

  void _openPage(BuildContext context, SandboxPage page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AcademySandboxPageScreen(
          bloc: widget.bloc,
          module: widget.module,
          page: page,
          secureFlagService: widget.secureFlagService,
        ),
      ),
    );
  }

  void _openEdit(BuildContext context, SandboxPage? page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AcademySandboxEditScreen(
          bloc: widget.bloc,
          module: widget.module,
          page: page,
          secureFlagService: widget.secureFlagService,
        ),
      ),
    );
  }
}

class _EmptyWiki extends StatelessWidget {
  final bool hasQuery;
  final VoidCallback onCreate;

  const _EmptyWiki({required this.hasQuery, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.edit_note_rounded,
                size: 36, color: AcademyTheme.muted),
            const SizedBox(height: 10),
            Text(
              hasQuery
                  ? 'No pages match the search.'
                  : 'No sandbox pages yet — start the community study notes.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AcademyTheme.ink),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: AcademyTheme.emerald,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text(
                'NEW PAGE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  final VoidCallback onRetry;

  const _FailureView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Unable to load the sandbox wiki.',
            style: TextStyle(fontSize: 13, color: AcademyTheme.ink),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AcademyTheme.emerald,
            ),
            child: const Text('RETRY',
                style: TextStyle(fontFamily: AcademyTheme.monoFont)),
          ),
        ],
      ),
    );
  }
}
