import 'package:flutter/material.dart';

import '../../war_room/domain/case_severity.dart';
import 'war_case_severity_band.dart';
import 'war_room_theme.dart';

/// The War Room dossier masthead (DESIGN.md §2.2/§8.2).
///
/// A dossier stamp bar: `▌WAR ROOM▐` + optional section label (`YOUR CASES`)
/// + optional case stamp (`CASE #CC-0047`) + optional severity band, over
/// the `CIVIC COMMONS OSINT UNIT — SECURE CHANNEL` subtitle, closed by a
/// charcoal stamp rule.
///
/// SECURITY CHECKPOINT (Task 8.1): the masthead renders ONLY fixed labels,
/// the public case number, and the severity classification — no phones, no
/// names, no handles, no hashes ever appear here.
class WarRoomMasthead extends StatelessWidget {
  const WarRoomMasthead({
    super.key,
    this.label,
    this.caseNumber,
    this.severity,
  });

  /// Optional section label rendered after the title (e.g. `YOUR CASES`).
  final String? label;

  /// Optional dossier stamp (`CC-0047`), rendered as `CASE #CC-0047`.
  final String? caseNumber;

  /// Optional severity band (detail view: `CASE #CC-0047 ⬛ HIGH`).
  final CaseSeverity? severity;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final caseNumber = this.caseNumber;
    final severity = this.severity;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: WarRoomTheme.dossierInk,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '▌WAR ROOM▐',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFamily: WarRoomTheme.monoFont,
                      letterSpacing: 1.4,
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
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: WarRoomTheme.monoFont,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                  if (caseNumber != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text(
                        'CASE #$caseNumber',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: WarRoomTheme.monoFont,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  if (severity != null) ...[
                    const SizedBox(width: 8),
                    WarCaseSeverityBand(severity: severity, compact: true),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'CIVIC COMMONS OSINT UNIT — SECURE CHANNEL',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
        // Dossier stamp rule — the classified-file closure line.
        Container(
          height: 3,
          color: WarRoomTheme.dossierInk,
        ),
      ],
    );
  }
}
