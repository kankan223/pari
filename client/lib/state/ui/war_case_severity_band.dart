import 'package:flutter/material.dart';

import '../../war_room/domain/case_severity.dart';
import 'war_room_theme.dart';

/// The severity classification band (DESIGN.md §8.2: `▌HIGH SEVERITY`).
///
/// A colored mono strip labeled `CRITICAL SEVERITY` / `HIGH SEVERITY` /
/// `MEDIUM SEVERITY` / `LOW SEVERITY`. Severity is a PUBLIC case attribute
/// (PRD FR-W2) — the band can never leak identity or payload content.
class WarCaseSeverityBand extends StatelessWidget {
  final CaseSeverity severity;

  /// Compact mode renders the bare label (`HIGH`), used inside the masthead
  /// stamp row; the card/list mode renders `HIGH SEVERITY`.
  final bool compact;

  const WarCaseSeverityBand({
    super.key,
    required this.severity,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = WarRoomTheme.severityColor(severity);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        compact ? severity.label : '${severity.label} SEVERITY',
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
          fontFamily: WarRoomTheme.monoFont,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
