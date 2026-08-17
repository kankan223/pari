import 'package:flutter/material.dart';

import 'academy_theme.dart';

/// UTC timestamp label for the Sandbox Wiki — e.g. `2026-08-17 14:30`.
/// Public, non-PII.
String sandboxTimeLabel(DateTime time) {
  final u = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} '
      '${two(u.hour)}:${two(u.minute)}';
}

/// The Sandbox's Markdown body renderer (Task 9.5).
///
/// The project has NO Markdown renderer package (zero new dependencies), so
/// the body is rendered as a mono preformatted block that preserves the
/// Markdown source — honest, dependency-free, and zero-rendering bugs. The
/// raw Markdown is community UGC already persisted inside the encrypted
/// partition; this view renders it read-only for the page detail + preview.
class AcademySandboxMarkdownView extends StatelessWidget {
  final String body;

  const AcademySandboxMarkdownView({super.key, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AcademyTheme.surface,
        border: Border.all(color: AcademyTheme.rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: SelectableText(
        body.isEmpty ? '_(empty draft)_' : body,
        style: const TextStyle(
          fontSize: 12,
          color: AcademyTheme.ink,
          fontFamily: AcademyTheme.monoFont,
          height: 1.5,
        ),
      ),
    );
  }
}
