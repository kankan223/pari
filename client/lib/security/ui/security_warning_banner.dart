import 'package:flutter/material.dart';

/// Visual warning shown when the local integrity check flags a device.
///
/// This is a *warning, not a block*: the banner informs the user that their
/// device appears modified and that they should exercise caution, but the
/// screen underneath remains fully usable.
///
/// Security contract:
/// - Displays only generic, non-fingerprinting copy. No device model, serial,
///   identifiers, or any telemetry is shown or transmitted.
class SecurityWarningBanner extends StatelessWidget {
  final String message;

  const SecurityWarningBanner({
    super.key,
    this.message = 'Your device appears to be modified (rooted/jailbroken). '
        'Proceed with caution.',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: colors.onErrorContainer, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
