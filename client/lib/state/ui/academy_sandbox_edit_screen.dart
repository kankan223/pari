import 'package:flutter/material.dart';

import '../../academy/domain/academy_module.dart';
import '../../academy/domain/sandbox_wiki.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/sandbox_wiki_bloc.dart';
import '../domain/sandbox_wiki_state.dart';
import 'academy_sandbox_wiki_format.dart';
import 'academy_theme.dart';

/// The Sandbox Markdown editor (Task 9.5 — Markdown editor for Sandbox
/// contributions).
///
/// A plain Markdown source editor (zero new dependencies — the project has
/// no Markdown renderer package) with BOLD / HEADING / LINK syntax insert
/// chips, a PREVIEW toggle (the raw Markdown rendered read-only via
/// [AcademySandboxMarkdownView]) and SAVE, which submits the draft through
/// the bloc as a new revision (creating the page when none is open).
///
/// SECURITY CHECKPOINT (Task 9.5): the editor shows the `SA-####` handle
/// for the module — never identity; the draft lives only in the bloc's
/// in-memory state until SAVE persists it inside the encrypted partition.
/// Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class AcademySandboxEditScreen extends StatefulWidget {
  final SandboxWikiBloc bloc;
  final AcademyModule module;

  /// The page being edited, or null when creating a new page.
  final SandboxPage? page;

  /// Injectable FLAG_SECURE service (test seam) — null uses production.
  final SecureFlagService? secureFlagService;

  const AcademySandboxEditScreen({
    super.key,
    required this.bloc,
    required this.module,
    this.page,
    this.secureFlagService,
  });

  @override
  State<AcademySandboxEditScreen> createState() =>
      _AcademySandboxEditScreenState();
}

class _AcademySandboxEditScreenState extends State<AcademySandboxEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    final bloc = widget.bloc;
    final page = widget.page;
    final state = bloc.current;
    _title = TextEditingController(text: page?.title ?? '');
    _body = TextEditingController(
      text: state.draftBody.isNotEmpty
          ? state.draftBody
          : _latestBodyFrom(state, page),
    );
    _loadLatestBody();
  }

  /// The latest revision body if [state] already holds the page's history.
  static String _latestBodyFrom(SandboxWikiState state, SandboxPage? page) {
    if (page == null || state.selectedPage?.pageId != page.pageId) {
      return '';
    }
    return state.revisions.isEmpty ? '' : state.revisions.last.bodyMarkdown;
  }

  /// Opens the page's revision history when the editor is entered directly
  /// (the wiki screen always opens the detail first, but a deep link or
  /// direct composition must still pre-fill the latest body). The bloc is
  /// the only data path — no repository access from the UI.
  Future<void> _loadLatestBody() async {
    final page = widget.page;
    if (page == null) {
      return;
    }
    await widget.bloc.openPage(page.pageId);
    if (!mounted) {
      return;
    }
    final state = widget.bloc.current;
    if (state.revisions.isNotEmpty && _body.text.isEmpty) {
      _body.text = state.revisions.last.bodyMarkdown;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  void _insertSyntax(String prefix, String suffix) {
    final value = _body.text;
    final selection = _body.selection;
    final start = selection.isValid ? selection.start : value.length;
    final end = selection.isValid ? selection.end : value.length;
    final selected = value.substring(start, end);
    final replacement = '$prefix$selected$suffix';
    _body.text = value.replaceRange(start, end, replacement);
    _body.selection = TextSelection.collapsed(offset: start + prefix.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AcademyTheme.paper,
      appBar: AppBar(
        backgroundColor: AcademyTheme.paper,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.page == null ? 'NEW SANDBOX PAGE' : 'EDIT SANDBOX PAGE',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AcademyTheme.ink,
            fontFamily: AcademyTheme.monoFont,
            letterSpacing: 0.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _preview = !_preview),
            child: Text(
              _preview ? 'WRITE' : 'PREVIEW',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AcademyTheme.emerald,
                fontFamily: AcademyTheme.monoFont,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _secure(
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  'Editing as ${widget.bloc.current.authorHandle} · Markdown',
                  style:
                      const TextStyle(fontSize: 11, color: AcademyTheme.muted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: TextField(
                  controller: _title,
                  style: const TextStyle(fontSize: 15, color: AcademyTheme.ink),
                  decoration: const InputDecoration(
                    labelText: 'Page title',
                    labelStyle:
                        TextStyle(fontSize: 12, color: AcademyTheme.muted),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AcademyTheme.rule)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AcademyTheme.emerald)),
                  ),
                ),
              ),
              // Syntax insert chips (zero dependencies — plain text insert).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _SyntaxChip(
                        label: 'BOLD', onTap: () => _insertSyntax('**', '**')),
                    const SizedBox(width: 6),
                    _SyntaxChip(
                        label: 'HEADING', onTap: () => _insertSyntax('# ', '')),
                    const SizedBox(width: 6),
                    _SyntaxChip(
                        label: 'LINK',
                        onTap: () => _insertSyntax('[', '](url)')),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _preview
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SingleChildScrollView(
                          child: AcademySandboxMarkdownView(body: _body.text),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _body,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AcademyTheme.ink,
                            fontFamily: AcademyTheme.monoFont,
                            height: 1.5,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Write the study notes in Markdown…\n\n'
                                '# Heading\n\n**bold** and [links](url)',
                            hintStyle: const TextStyle(
                                fontSize: 12, color: AcademyTheme.muted),
                            filled: true,
                            fillColor: AcademyTheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(3),
                              borderSide:
                                  const BorderSide(color: AcademyTheme.rule),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(3),
                              borderSide:
                                  const BorderSide(color: AcademyTheme.rule),
                            ),
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AcademyTheme.emerald,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  child: const Text(
                    'SAVE REVISION',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: AcademyTheme.monoFont,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a page title to save.')),
      );
      return;
    }
    widget.bloc.setDraft(_body.text);
    await widget.bloc.submitDraft(title: title);
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }
}

class _SyntaxChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SyntaxChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AcademyTheme.surface,
          border: Border.all(color: AcademyTheme.rule),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AcademyTheme.emerald,
            fontFamily: AcademyTheme.monoFont,
          ),
        ),
      ),
    );
  }
}
