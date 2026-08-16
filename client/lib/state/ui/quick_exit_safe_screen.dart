import 'package:flutter/material.dart';

import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import 'war_room_theme.dart';

/// The neutral, safe fallback screen reached by QUICK EXIT (Task 8.7).
///
/// When a victim hits the panic button the intake/detail screens instantly
/// wipe their transient state and navigate here: a calm, non-War-Room
/// surface with NO case data, NO dossier stamps, NO evidence — nothing that
/// could reveal what they were doing. The host wires [onDone] to return to
/// the app home / vault shell.
///
/// SECURITY CHECKPOINT (Task 8.7): the screen is FLAG_SECURE wrapped, shows
/// zero case content, and carries no transient buffers to wipe (the wipe
/// happened on the source screen before navigation).
class QuickExitSafeScreen extends StatelessWidget {
  /// Returns the victim to the app shell (host wiring).
  final VoidCallback? onDone;

  /// FLAG_SECURE service seam (tests inject a recording fake).
  final SecureFlagService? secureFlagService;

  const QuickExitSafeScreen({super.key, this.onDone, this.secureFlagService});

  @override
  Widget build(BuildContext context) {
    final child = Scaffold(
      backgroundColor: const Color(0xFFF4F1EA),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shield_outlined,
                    size: 48, color: WarRoomTheme.muted),
                const SizedBox(height: 18),
                const Text(
                  'You are safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: WarRoomTheme.dossierInk,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The screen was cleared. Nothing you were typing '
                  'or viewing is on this screen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: WarRoomTheme.muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: onDone ?? () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: WarRoomTheme.dossierInk,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                  ),
                  child: const Text('Return to home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final flag = secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }
}
