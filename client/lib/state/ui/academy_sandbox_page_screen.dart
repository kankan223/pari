import 'package:flutter/material.dart';

import '../../academy/domain/academy_module.dart';
import '../../academy/domain/sandbox_wiki.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/sandbox_wiki_bloc.dart';
import '../domain/sandbox_wiki_state.dart';
import 'academy_sandbox_edit_screen.dart';
import 'academy_sandbox_wiki_format.dart';
import 'academy_theme.dart';

/// The Sandbox Wiki page detail screen (Task 9.5).
///
/// Renders the page's current Markdown body + the append-only REVISION
/// HISTORY: every revision shows its `SA-####` author handle, timestamp and
/// the deterministic diff summary (`+A −R`) against the previous revision
/// (PRD FR-A3 — every revision diffable + revertible). REVERT appends a new
/// revision with the target's body; EDIT opens the Markdown editor.
///
/// SECURITY CHECKPOINT (Task 9.5): the screen renders ONLY the page title,
/// the body (community UGC shown from the local encrypted store), the
/// `SA-####` handles, timestamps and diff COUNTS — zero identity, zero PII.
/// Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class AcademySandboxPageScreen extends StatefulWidget {
  final SandboxWikiBloc bloc;
  final AcademyModule module;
  final SandboxPage page;

  /// Injectable FLAG_SECURE service (test seam) — null uses production.
  final SecureFlagService? secureFlagService;

  const AcademySandboxPageScreen({
    super.key,
    required this.bloc,
    required this.module,
    required this.page,
    this.secureFlagService,
  });

  @override
  State<AcademySandboxPageScreen> createState() =>
      _AcademySandboxPageScreenState();
}

class _AcademySandboxPageScreenState extends State<AcademySandboxPageScreen> {
  @override
  void initState() {
    super.initState();
    widget.bloc.openPage(widget.page.pageId);
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
          tooltip: 'Back to sandbox wiki',
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
            final state = snapshot.data ?? widget.bloc.current;
            final page = state.selectedPage ?? widget.page;
            final revisions = state.revisions;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  page.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AcademyTheme.ink,
                    fontFamily: AcademyTheme.serifFont,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${page.revisionCount} revision'
                  '${page.revisionCount == 1 ? '' : 's'} · '
                  '${sandboxTimeLabel(page.updatedAt)}',
                  style:
                      const TextStyle(fontSize: 11, color: AcademyTheme.muted),
                ),
                const SizedBox(height: 12),
                // The current body (read-only Markdown source).
                AcademySandboxMarkdownView(
                    body: revisions.isEmpty ? '' : revisions.last.bodyMarkdown),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openEdit(context, page),
                      style: FilledButton.styleFrom(
                        backgroundColor: AcademyTheme.emerald,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Icons.edit_rounded, size: 14),
                      label: const Text(
                        'EDIT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: AcademyTheme.monoFont,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AcademyTheme.rule),
                const SizedBox(height: 6),
                const Text(
                  'REVISION HISTORY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AcademyTheme.ink,
                    fontFamily: AcademyTheme.monoFont,
                  ),
                ),
                const SizedBox(height: 8),
                ..._revisionEntries(revisions),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _revisionEntries(List<SandboxRevision> revisions) {
    if (revisions.isEmpty) {
      return const [
        Text(
          'No revisions yet.',
          style: TextStyle(fontSize: 12, color: AcademyTheme.muted),
        ),
      ];
    }
    return [
      for (var i = 0; i < revisions.length; i++)
        _revisionCard(
          revisions[i],
          i == 0 ? null : revisions[i - 1],
          isLatest: i == revisions.length - 1,
        ),
    ];
  }

  Widget _revisionCard(SandboxRevision revision, SandboxRevision? previous,
      {required bool isLatest}) {
    final diff = previous == null
        ? null
        : SandboxLineDiff.diff(previous.bodyMarkdown, revision.bodyMarkdown);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AcademyTheme.surface,
        border: Border.all(color: AcademyTheme.rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${revision.authorHandle} · '
                  '${sandboxTimeLabel(revision.createdAt)}',
                  style: const TextStyle(fontSize: 11, color: AcademyTheme.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  diff == null ? 'first revision' : 'diff ${diff.summary}',
                  style:
                      const TextStyle(fontSize: 11, color: AcademyTheme.muted),
                ),
              ],
            ),
          ),
          if (isLatest)
            const Text(
              'CURRENT',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AcademyTheme.emerald,
                fontFamily: AcademyTheme.monoFont,
              ),
            )
          else
            TextButton(
              onPressed: () => widget.bloc.revertTo(revision.revisionId),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'REVERT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AcademyTheme.ink,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openEdit(BuildContext context, SandboxPage page) {
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
