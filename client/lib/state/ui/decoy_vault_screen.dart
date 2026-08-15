import 'package:flutter/material.dart';

import '../../security/domain/root_detection_service.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import 'vault_empty_state.dart';
import 'vault_masthead.dart';
import 'vault_theme.dart';

/// The DECOY vault screen (Task 6.6) — shown when the DURESS PIN opens the
/// decoy vault.
///
/// Renders a vault conversation list that is VISUALLY IDENTICAL to the real
/// one but always EMPTY: the same [VaultMasthead], the same "CONVERSATIONS"
/// header, and the same [VaultEmptyState] copy as a freshly-registered real
/// vault. An observer cannot distinguish a duress-unlocked decoy from a
/// real vault that simply has no conversations yet.
///
/// SECURITY CHECKPOINT (Task 6.6):
/// - The screen takes NO data and NO bloc — there is nothing real to leak.
/// - Every string is the fixed, non-PII copy shared with the real vault.
/// - Wrapped in [SecureScreenWrapper] (FLAG_SECURE), same as every Vault
///   screen — the decoy must not be distinguishable by its security guard
///   either.
class DecoyVaultScreen extends StatelessWidget {
  const DecoyVaultScreen({
    super.key,
    this.secureFlagService,
    this.rootDetectionService,
  });

  final SecureFlagService? secureFlagService;
  final RootDetectionService? rootDetectionService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _secure(
      Scaffold(
        body: Column(
          children: [
            const VaultMasthead(),
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Text(
                      'CONVERSATIONS',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: VaultTheme.vaultBlue,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const VaultEmptyState(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wraps in [SecureScreenWrapper] (FLAG_SECURE), mirroring every Vault
  /// screen (Task 6.1 convention).
  Widget _secure(Widget child) {
    final flag = secureFlagService;
    final rootDetectionService = this.rootDetectionService;
    return flag == null
        ? SecureScreenWrapper(
            rootDetectionService: rootDetectionService, child: child)
        : SecureScreenWrapper(
            secureFlagService: flag,
            rootDetectionService: rootDetectionService,
            child: child,
          );
  }
}
