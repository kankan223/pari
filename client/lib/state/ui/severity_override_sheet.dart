import 'package:flutter/material.dart';

import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../../war_room/domain/case_severity.dart';
import '../../war_room/domain/severity_scoring.dart';
import 'war_room_theme.dart';

/// Human-review severity override sheet (Task 8.4 — "severity override UI
/// for human review").
///
/// The analyst picks the corrected severity band and MUST provide a reason
/// (the reason is analyst annotation — case content, never identity). On
/// confirm the [onOverride] callback receives the [SeverityOverride] which
/// the bloc applies via the repository. The sheet is wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE).
class SeverityOverrideSheet extends StatefulWidget {
  final CaseSeverity currentSeverity;
  final ValueChanged<SeverityOverride> onOverride;
  final SecureFlagService? secureFlagService;

  const SeverityOverrideSheet({
    super.key,
    required this.currentSeverity,
    required this.onOverride,
    this.secureFlagService,
  });

  @override
  State<SeverityOverrideSheet> createState() => _SeverityOverrideSheetState();
}

class _SeverityOverrideSheetState extends State<SeverityOverrideSheet> {
  CaseSeverity? _selected;
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canConfirm => _selected != null && _reason.text.trim().isNotEmpty;

  void _confirm() {
    final selected = _selected;
    if (selected == null || _reason.text.trim().isEmpty) {
      return;
    }
    widget.onOverride(SeverityOverride(
      newSeverity: selected,
      reason: _reason.text.trim(),
      at: DateTime.now(),
    ));
    Navigator.of(context).pop();
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  @override
  Widget build(BuildContext context) {
    // Bound the WHOLE secured sheet to 80% of the viewport (the modal allows
    // full-screen height and SecureScreenWrapper expands its child — the
    // constraint must wrap the wrapper, not sit inside it) so the severity
    // radios + reason + apply stay inside the tappable area.
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: _secure(
        SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OVERRIDE SEVERITY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFamily: WarRoomTheme.monoFont,
                  letterSpacing: 1.4,
                  color: WarRoomTheme.muted,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Correct the auto-score for human review. The original triage '
                'stays on the case for the audit trail.',
                style: TextStyle(fontSize: 13, color: WarRoomTheme.dossierInk),
              ),
              const SizedBox(height: 12),
              RadioGroup<CaseSeverity>(
                groupValue: _selected,
                onChanged: (v) => setState(() => _selected = v),
                child: Column(
                  children: [
                    for (final s in CaseSeverity.values)
                      RadioListTile<CaseSeverity>(
                        title: Text(
                          '${s.label}  ·  ${SeverityScorer.slaHoursFor(s)}h SLA',
                          style: const TextStyle(fontSize: 13),
                        ),
                        value: s,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Reason for the override (required)…',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: WarRoomTheme.surface,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canConfirm ? _confirm : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: WarRoomTheme.amber,
                    disabledBackgroundColor: WarRoomTheme.divider,
                  ),
                  child: const Text('Apply override'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
