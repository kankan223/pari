import 'package:flutter/material.dart';

import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../../war_room/domain/analyst.dart';
import '../../war_room/domain/case_status.dart';
import '../../war_room/domain/custody_log.dart';
import '../../war_room/domain/severity_scoring.dart';
import '../../war_room/domain/war_room_case.dart';
import '../domain/war_room_bloc.dart';
import '../domain/war_room_state.dart';
import 'quick_exit_safe_screen.dart';
import 'severity_override_sheet.dart';
import 'verified_intel_report_sheet.dart';
import 'war_case_severity_band.dart';
import 'war_room_masthead.dart';
import 'war_room_theme.dart';

/// The War Room active case / investigation view (DESIGN.md §8.4).
///
/// Renders the status timeline (filed → auto-triage → analysts assigned →
/// investigation ongoing → report ready), blinded analyst updates, and the
/// victim's always-visible one-tap controls ([Pause case] / [Add more
/// evidence] / [Withdraw]).
///
/// SECURITY CHECKPOINT (Task 8.1): whole screen wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE). Timeline entries, analyst counts,
/// and update texts are case content — never analyst/victim identity.
class WarCaseDetailScreen extends StatefulWidget {
  const WarCaseDetailScreen({
    super.key,
    required this.bloc,
    required this.caseNumber,
    this.onAddEvidence,
    this.onReport,
    this.onQuickExit,
    this.secureFlagService,
  });

  final WarRoomBloc bloc;

  /// The dossier stamp of the opened case.
  final String caseNumber;

  /// Evidence attach flow (wired in Task 8.2 — encrypted upload).
  final VoidCallback? onAddEvidence;

  /// Verified Intel Report open (wired in Task 8.6).
  final VoidCallback? onReport;

  /// QUICK EXIT / panic button (Task 8.7): instantly leaves the case view
  /// to a neutral safe screen. When null, the screen pushes
  /// [QuickExitSafeScreen] itself; the host may wire this to exit the vault
  /// shell instead.
  final VoidCallback? onQuickExit;

  /// FLAG_SECURE service seam (tests inject a recording fake).
  final SecureFlagService? secureFlagService;

  @override
  State<WarCaseDetailScreen> createState() => _WarCaseDetailScreenState();
}

class _WarCaseDetailScreenState extends State<WarCaseDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Self-contained for the composition root: opens the case so the
    // StreamBuilder below (broadcast — no replay) receives the selection.
    widget.bloc.openCase(widget.caseNumber);
  }

  /// QUICK EXIT / panic (Task 8.7): instantly leaves the case view to the
  /// neutral safe screen. The detail holds no transient text buffers (case
  /// data lives in the repo) — navigation is the wipe.
  Future<void> _quickExit() async {
    final onQuickExit = widget.onQuickExit;
    if (onQuickExit != null) {
      onQuickExit();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuickExitSafeScreen(
          secureFlagService: widget.secureFlagService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bloc = widget.bloc;
    return Scaffold(
      backgroundColor: WarRoomTheme.manilaPaper,
      body: _secure(
        StreamBuilder<WarRoomState>(
          stream: bloc.state,
          builder: (context, snapshot) {
            final selected = snapshot.data?.selected;
            if (selected == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _CaseDetailBody(
              summary: selected,
              onAddEvidence: widget.onAddEvidence,
              onQuickExit: _quickExit,
              onReport: () {
                // The report slot deferred in Task 8.1 is wired here (8.6):
                // open the HMAC-signed Verified Intel Report sheet, then
                // fire the optional external navigation hook.
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: WarRoomTheme.manilaPaper,
                  isScrollControlled: true,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  builder: (_) => VerifiedIntelReportSheet(
                    bloc: bloc,
                    caseNumber: selected.caseNumber,
                    secureFlagService: widget.secureFlagService,
                  ),
                );
                widget.onReport?.call();
              },
              onPause: () =>
                  bloc.setPaused(selected.caseNumber, !selected.paused),
              onWithdraw: () => bloc.withdraw(selected.caseNumber),
              onOverrideSeverity: (override) =>
                  bloc.overrideSeverity(selected.caseNumber, override),
            );
          },
        ),
      ),
    );
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }
}

class _CaseDetailBody extends StatelessWidget {
  final WarRoomCaseSummary summary;
  final VoidCallback? onAddEvidence;
  final VoidCallback? onReport;
  final VoidCallback? onQuickExit;
  final VoidCallback onPause;
  final VoidCallback onWithdraw;

  /// Applies a human-review severity override (Task 8.4).
  final ValueChanged<SeverityOverride> onOverrideSeverity;

  const _CaseDetailBody({
    required this.summary,
    required this.onPause,
    required this.onWithdraw,
    required this.onOverrideSeverity,
    this.onAddEvidence,
    this.onReport,
    this.onQuickExit,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Column(
      children: [
        WarRoomMasthead(
          caseNumber: s.caseNumber,
          severity: s.severity,
        ),
        // QUICK EXIT panic button (Task 8.7) — always reachable above the
        // scrollable case content.
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: TextButton(
              onPressed: onQuickExit,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB52A2A),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.exit_to_app, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'QUICK EXIT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      fontFamily: WarRoomTheme.monoFont,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                s.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: WarRoomTheme.dossierInk,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.description,
                style: const TextStyle(
                  fontSize: 14,
                  color: WarRoomTheme.dossierInk,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  WarCaseSeverityBand(severity: s.severity),
                  const SizedBox(width: 10),
                  Text(
                    '${s.analystCount} analyst'
                    '${s.analystCount == 1 ? '' : 's'} assigned',
                    style: const TextStyle(
                        fontSize: 12, color: WarRoomTheme.muted),
                  ),
                  if (s.paused) ...[
                    const SizedBox(width: 8),
                    const _StatusChip('PAUSED')
                  ],
                  if (s.status == CaseStatus.withdrawn) ...[
                    const SizedBox(width: 8),
                    const _StatusChip('WITHDRAWN')
                  ],
                ],
              ),
              if (s.triage != null) ...[
                const SizedBox(height: 18),
                _TriageSection(
                  triage: s.triage!,
                  appliedOverride: s.severityOverride,
                  onOverride: () => _openOverrideSheet(context),
                ),
              ],
              if (s.assignments.isNotEmpty) ...[
                const SizedBox(height: 18),
                _AnalystTeamSection(assignments: s.assignments),
              ],
              if (s.custodyEvents.isNotEmpty) ...[
                const SizedBox(height: 18),
                _CustodySection(events: s.custodyEvents),
              ],
              const SizedBox(height: 18),
              const _SectionHeader('STATUS TIMELINE'),
              const SizedBox(height: 8),
              ...s.timeline.map((e) => _TimelineRow(entry: e)),
              const SizedBox(height: 18),
              if (s.updates.isNotEmpty) ...[
                const _SectionHeader('ANALYST UPDATE'),
                const SizedBox(height: 8),
                ...s.updates.map((u) => _AnalystUpdateCard(update: u)),
                const SizedBox(height: 18),
              ],
              const Text(
                'You can pause or withdraw this case at any time.',
                style: TextStyle(
                  fontSize: 12,
                  color: WarRoomTheme.muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onPause,
                      child: Text(s.paused ? 'Resume case' : 'Pause case'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onAddEvidence,
                      child: const Text('Add more evidence'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onWithdraw,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB52A2A),
                      ),
                      child: const Text('Withdraw'),
                    ),
                  ),
                ],
              ),
              if (onReport != null && s.status != CaseStatus.withdrawn) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onReport,
                  style: FilledButton.styleFrom(
                    backgroundColor: WarRoomTheme.amber,
                  ),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Verified Intel Report'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openOverrideSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WarRoomTheme.manilaPaper,
      isScrollControlled: true,
      // Bound the sheet to 80% of the viewport so its scrollable content
      // (severity radios + reason + apply) is fully reachable — an
      // unbounded isScrollControlled sheet clips content below the visible
      // area and its controls become untappable.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      builder: (_) => SeverityOverrideSheet(
        currentSeverity: summary.severity,
        onOverride: onOverrideSeverity,
      ),
    );
  }
}

/// The Task 8.4 triage section: the deterministic auto-score, its non-PII
/// signal counts, the SLA projection, and the human-review override entry
/// point. Renders ONLY public severity attributes + signal COUNTS — never
/// the matched keywords, never payload content.
class _TriageSection extends StatelessWidget {
  final SeverityTriage triage;
  final SeverityOverride? appliedOverride;
  final VoidCallback onOverride;

  const _TriageSection({
    required this.triage,
    required this.appliedOverride,
    required this.onOverride,
  });

  @override
  Widget build(BuildContext context) {
    final appliedOverride = this.appliedOverride;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('SEVERITY TRIAGE'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: WarRoomTheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: WarRoomTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  WarCaseSeverityBand(severity: triage.severity),
                  const SizedBox(width: 10),
                  Text(
                    'SLA ${triage.slaHours}h',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: WarRoomTheme.monoFont,
                      color: WarRoomTheme.muted,
                    ),
                  ),
                  if (appliedOverride != null) ...[
                    const SizedBox(width: 8),
                    const _OverrideChip(),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              if (triage.signalLabels.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in triage.signalLabels) _SignalChip(label),
                  ],
                )
              else
                const Text(
                  'No signal keywords matched — scored on intake context.',
                  style: TextStyle(
                    fontSize: 12,
                    color: WarRoomTheme.muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              if (appliedOverride != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Override: ${appliedOverride.newSeverity.label} — '
                  '${appliedOverride.reason}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: WarRoomTheme.dossierInk,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onOverride,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(appliedOverride == null
                    ? 'Override severity'
                    : 'Change override'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The Task 8.5 analyst team section: the skill-matched, blinded team on
/// the case. Renders ONLY blinded `AN-####` handles + skill labels — never
/// names, emails, phones, or hashes (SECURITY CHECKPOINT 8.5: analyst
/// identities are blinded to victims).
class _AnalystTeamSection extends StatelessWidget {
  final List<CaseAssignment> assignments;

  const _AnalystTeamSection({required this.assignments});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('ANALYST TEAM'),
        const SizedBox(height: 8),
        ...assignments.map((a) => _TeamRow(assignment: a)),
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  final CaseAssignment assignment;

  const _TeamRow({required this.assignment});

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: WarRoomTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WarRoomTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: WarRoomTheme.dossierInk,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              a.analystId,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFamily: WarRoomTheme.monoFont,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              a.skill.label,
              style: const TextStyle(
                fontSize: 12,
                color: WarRoomTheme.dossierInk,
              ),
            ),
          ),
          const Text(
            'VETTED',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              fontFamily: WarRoomTheme.monoFont,
              letterSpacing: 0.8,
              color: Color(0xFF1E6B3A),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Task 8.6 CHAIN OF CUSTODY section: the append-only, tamper-evident
/// event chain for the case. Renders ONLY fixed event labels + timestamps +
/// blinded actors (`VICTIM` / `AN-####`) — never names, never payload
/// content (SECURITY CHECKPOINT 8.6: the custody log is immutable and
/// zero-PII).
class _CustodySection extends StatelessWidget {
  final List<CustodyEvent> events;

  const _CustodySection({required this.events});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('CHAIN OF CUSTODY'),
        const SizedBox(height: 8),
        ...events.map((e) => _CustodyRow(event: e)),
        const Text(
          'Append-only · hash-chained — tamper-evident.',
          style: TextStyle(
            fontSize: 11,
            color: WarRoomTheme.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _CustodyRow extends StatelessWidget {
  final CustodyEvent event;

  const _CustodyRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final e = event;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 14, color: WarRoomTheme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.type.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: WarRoomTheme.dossierInk,
                  ),
                ),
                Text(
                  '${e.actor}  ·  ${e.at.day}/${e.at.month} ${e.at.hour}:'
                  '${e.at.minute.toString().padLeft(2, '0')}  ·  '
                  'chain ${e.selfHash.substring(0, 8)}…',
                  style:
                      const TextStyle(fontSize: 11, color: WarRoomTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  final String label;
  const _SignalChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WarRoomTheme.amber),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontFamily: WarRoomTheme.monoFont,
          color: WarRoomTheme.dossierInk,
        ),
      ),
    );
  }
}

class _OverrideChip extends StatelessWidget {
  const _OverrideChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: WarRoomTheme.dossierInk,
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        'OVERRIDDEN',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFamily: WarRoomTheme.monoFont,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        fontFamily: WarRoomTheme.monoFont,
        letterSpacing: 1.4,
        color: WarRoomTheme.muted,
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final CaseTimelineEntry entry;
  const _TimelineRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final done = entry.done;
    final at = entry.at;
    final marker = done
        ? const Icon(Icons.check_circle, size: 16, color: Color(0xFF1E6B3A))
        : const Icon(Icons.radio_button_unchecked,
            size: 16, color: WarRoomTheme.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          marker,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: done ? FontWeight.w700 : FontWeight.w400,
                    color: WarRoomTheme.dossierInk,
                  ),
                ),
                if (at != null || entry.detail != null)
                  Text(
                    [
                      if (at != null)
                        '${at.day}/${at.month} ${at.hour}:${at.minute.toString().padLeft(2, '0')}',
                      if (entry.detail != null) entry.detail!,
                    ].join('  ·  '),
                    style: const TextStyle(
                        fontSize: 11, color: WarRoomTheme.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small dossier status chip (paused / withdrawn markers).
class _StatusChip extends StatelessWidget {
  final String label;
  const _StatusChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: WarRoomTheme.dossierInk,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFamily: WarRoomTheme.monoFont,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _AnalystUpdateCard extends StatelessWidget {
  final AnalystUpdate update;
  const _AnalystUpdateCard({required this.update});

  @override
  Widget build(BuildContext context) {
    final u = update;
    return Card(
      elevation: 0,
      color: WarRoomTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: WarRoomTheme.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              u.text,
              style:
                  const TextStyle(fontSize: 13, color: WarRoomTheme.dossierInk),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${u.analystId}  ·  ${u.at.day}/${u.at.month} ${u.at.hour}:'
                  '${u.at.minute.toString().padLeft(2, '0')}',
                  style:
                      const TextStyle(fontSize: 11, color: WarRoomTheme.muted),
                ),
                const Spacer(),
                Text(
                  u.progress.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: WarRoomTheme.monoFont,
                    letterSpacing: 0.8,
                    color: WarRoomTheme.amber,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
