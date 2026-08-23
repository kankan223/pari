import 'package:flutter/material.dart';

import 'vault_theme.dart';

/// The Vault pillar masthead (DESIGN.md §2.2/§6.2).
///
/// A classified-briefing strip: Vault Blue background, a lock glyph, the
/// "THE VAULT" wordmark (tracked caps), a `[CLASSIFIED]` stamp, optional
/// contextual meta (e.g. the local user's display handle) and an optional
/// action (the "new conversation" affordance), above a solid black
/// pseudo-redaction bar.
///
/// SECURITY CHECKPOINT (Task 6.1): the masthead renders ONLY fixed labels,
/// the lock icon, and [contextMeta] — which callers MUST populate through
/// [formatPeerHandle] (never raw hashes, phones, or usernames). The
/// redaction bar is decorative fixed text; it never carries real content.
class VaultMasthead extends StatelessWidget {
  const VaultMasthead({
    super.key,
    this.contextMeta,
    this.onAction,
    this.onSettings,
    this.onSearch,
  });

  /// Optional trailing identity line, e.g. the local user's display handle
  /// (must already be PII-free — see [formatPeerHandle]).
  final String? contextMeta;

  /// Optional trailing action (the "new conversation" CTA). When null, the
  /// action button is not rendered.
  final VoidCallback? onAction;

  /// Optional settings action. When null, the settings button is not rendered.
  final VoidCallback? onSettings;

  /// Optional search action. When null, the search button is not rendered.
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: VaultTheme.vaultBlue,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.lock_rounded, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'THE VAULT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              _ClassifiedStamp(),
              if (contextMeta != null) ...[
                const SizedBox(width: 10),
                Text(
                  contextMeta!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: VaultTheme.monoFont,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
              if (onSettings != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_outlined,
                      color: Colors.white70, size: 20),
                  tooltip: 'Settings',
                  visualDensity: VisualDensity.compact,
                ),
              ],
              if (onAction != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 22),
                  tooltip: 'New conversation',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
        // Pseudo-redaction bar: solid black with decorative fixed marks.
        Container(
          height: 14,
          color: VaultTheme.redactionBlack,
          child: const Center(
            child: Text(
              '████ ████ ████ PRIVATE ████ ████',
              style: TextStyle(
                color: Colors.white24,
                fontSize: 8,
                fontFamily: VaultTheme.monoFont,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fixed `[CLASSIFIED]` stamp.
class _ClassifiedStamp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white54, width: 0.6),
      ),
      child: const Text(
        'CLASSIFIED',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          fontFamily: VaultTheme.monoFont,
        ),
      ),
    );
  }
}
