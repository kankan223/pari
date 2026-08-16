import 'package:flutter/material.dart';

import 'ledger_theme.dart';

/// The Ledger pillar masthead (DESIGN.md §2.2/§7.2).
///
/// A newspaper nameplate: Ledger Green background, the "THE DAILY LEDGER"
/// title set in a serif face, an edition marker (`EDITION 412`) and the
/// pin-code scope (`800001`), then a heavy black rule line beneath —
/// a newspaper says "this is the record for today"; so does the Ledger.
///
/// SECURITY CHECKPOINT (Task 7.1): the masthead renders ONLY fixed labels
/// + the [edition] number and [pinCode] scope. Pin codes are public civic
/// identifiers (the feed is scoped by them), NOT identity — no phones,
/// no names, no hashes ever appear here.
class LedgerMasthead extends StatelessWidget {
  const LedgerMasthead({
    super.key,
    this.edition,
    this.pinCode,
  });

  /// The edition number (`412`), rendered as `EDITION 412`. Null hides it.
  final int? edition;

  /// The pin-code scope (`800001`), rendered after the title. Null hides it.
  final String? pinCode;

  @override
  Widget build(BuildContext context) {
    final edition = this.edition;
    final pinCode = this.pinCode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: LedgerTheme.ledgerGreen,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              const Text(
                'THE DAILY LEDGER',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFamily: LedgerTheme.mastheadFont,
                  letterSpacing: 1.2,
                ),
              ),
              if (edition != null || pinCode != null) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    if (edition != null) 'EDITION $edition',
                    if (pinCode != null) pinCode,
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Heavy rule line — the broadsheet's masthead rule.
        Container(
          height: 3,
          color: LedgerTheme.ink,
        ),
      ],
    );
  }
}
