import 'package:flutter/material.dart';

import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import 'academy_theme.dart';

/// The Academy textbook masthead (DESIGN.md §9.1/§9.2, Phase 9
/// foundation scaffold, Task 8.8).
///
/// A print-register stamp bar: `❧ THE ACADEMY` + optional section label
/// (`BROWSE CURRICULUM`) + optional module count, over the
/// `CIVIC COMMONS OPEN EDUCATION — LEARN WITHOUT LIMITS` subtitle, closed
/// by an emerald chapter rule.
///
/// SECURITY CHECKPOINT (Phase 9): the masthead renders ONLY fixed labels
/// and public module COUNTS — no phones, no names, no handles, no hashes
/// ever appear here. Wrapped in [SecureScreenWrapper] (FLAG_SECURE) like
/// every War Room / Vault surface.
class AcademyMasthead extends StatelessWidget {
  final String? label;

  /// Public module count rendered as `N modules` when provided.
  final int? moduleCount;

  /// Injectable FLAG_SECURE service (test seam) — null uses the
  /// production default.
  final SecureFlagService? secureFlagService;

  const AcademyMasthead({
    super.key,
    this.label,
    this.moduleCount,
    this.secureFlagService,
  });

  Widget _secure(Widget child) {
    final flag = secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final moduleCount = this.moduleCount;
    return _secure(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: AcademyTheme.ink,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '❧ THE ACADEMY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: AcademyTheme.serifFont,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (label != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: AcademyTheme.monoFont,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'CIVIC COMMONS OPEN EDUCATION — LEARN WITHOUT LIMITS',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    fontFamily: AcademyTheme.monoFont,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          // The emerald chapter rule.
          Container(
            height: 3,
            color: AcademyTheme.emerald,
          ),
          if (moduleCount != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  Text(
                    '$moduleCount modules',
                    style: const TextStyle(
                      color: AcademyTheme.muted,
                      fontSize: 12,
                      fontFamily: AcademyTheme.monoFont,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
