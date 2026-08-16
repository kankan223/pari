import 'package:flutter/material.dart';

import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../../war_room/domain/case_status.dart';
import '../domain/war_room_bloc.dart';
import '../domain/war_room_state.dart';
import 'war_case_severity_band.dart';
import 'war_room_masthead.dart';
import 'war_room_theme.dart';

/// The War Room case list screen — victim view (DESIGN.md §8.2).
///
/// Consumes the [WarRoomBloc] state stream ONLY (clean architecture — no
/// repository/network access from the widget tree). Renders:
/// - the [WarRoomMasthead] (dossier stamp bar, `YOUR CASES` section),
/// - case cards with stamp number, title, severity band, filed date ·
///   status, analyst count · est. report,
/// - an empty state for first-time victims,
/// - a `[+ File a new case]` action (Civic Gold dossier accent).
///
/// SECURITY CHECKPOINT (Task 8.1): the whole screen is wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE). Cases render ONLY public dossier
/// attributes — stamp numbers, severity, timestamps, analyst COUNTS.
class WarRoomCaseListScreen extends StatefulWidget {
  const WarRoomCaseListScreen({
    super.key,
    required this.bloc,
    this.onCaseTap,
    this.onFileNewCase,
    this.secureFlagService,
  });

  final WarRoomBloc bloc;

  /// Opens a case detail for [caseNumber].
  final ValueChanged<String>? onCaseTap;

  /// Opens the new-case intake flow.
  final VoidCallback? onFileNewCase;

  /// FLAG_SECURE service seam (tests inject a recording fake; production
  /// defaults to the MethodChannel implementation).
  final SecureFlagService? secureFlagService;

  @override
  State<WarRoomCaseListScreen> createState() => _WarRoomCaseListScreenState();
}

class _WarRoomCaseListScreenState extends State<WarRoomCaseListScreen> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget: the bloc re-emits on load (broadcast stream).
    widget.bloc.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WarRoomTheme.manilaPaper,
      body: _secure(
        Column(
          children: [
            const WarRoomMasthead(label: 'Your Cases'),
            Expanded(
              child: StreamBuilder<WarRoomState>(
                stream: widget.bloc.state,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  if (state == null || state.status == WarRoomStatus.loading) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  if (state.status == WarRoomStatus.error) {
                    return const Center(
                      child: Text('Could not load your cases.'),
                    );
                  }
                  final cases = state.cases;
                  if (cases.isEmpty) {
                    return _EmptyState(onFileNewCase: widget.onFileNewCase);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                    itemCount: cases.length,
                    itemBuilder: (context, index) => _CaseCard(
                      summary: cases[index],
                      onTap: () =>
                          widget.onCaseTap?.call(cases[index].caseNumber),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onFileNewCase,
        backgroundColor: WarRoomTheme.amber,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('File a new case'),
      ),
    );
  }

  /// Wraps in [SecureScreenWrapper], defaulting to the production FLAG_SECURE
  /// service when the test seam is not injected.
  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }
}

/// A single dossier case card (DESIGN.md §8.2).
class _CaseCard extends StatelessWidget {
  final WarRoomCaseSummary summary;
  final VoidCallback onTap;

  const _CaseCard({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final statusLine = s.paused ? '${s.status.label} · PAUSED' : s.status.label;
    final est = s.estReportHours;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: WarRoomTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: WarRoomTheme.divider),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'CASE #${s.caseNumber}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: WarRoomTheme.monoFont,
                      letterSpacing: 0.8,
                      color: WarRoomTheme.dossierInk,
                    ),
                  ),
                  const Spacer(),
                  if (s.status == CaseStatus.withdrawn)
                    const _StatusTag(label: 'WITHDRAWN')
                  else if (s.paused)
                    const _StatusTag(label: 'PAUSED'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                s.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: WarRoomTheme.dossierInk,
                ),
              ),
              const SizedBox(height: 8),
              WarCaseSeverityBand(severity: s.severity),
              const SizedBox(height: 10),
              Text(
                'Filed: ${_fmtDate(s.filedAt)} · Status: $statusLine',
                style: const TextStyle(
                  fontSize: 12,
                  color: WarRoomTheme.muted,
                ),
              ),
              Text(
                est == null
                    ? '${s.analystCount} analyst${s.analystCount == 1 ? '' : 's'} assigned'
                    : '${s.analystCount} analyst${s.analystCount == 1 ? '' : 's'} assigned · Est. report: $est hrs',
                style: const TextStyle(
                  fontSize: 12,
                  color: WarRoomTheme.muted,
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'View case →',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: WarRoomTheme.amber,
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

class _StatusTag extends StatelessWidget {
  final String label;
  const _StatusTag({required this.label});

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

class _EmptyState extends StatelessWidget {
  final VoidCallback? onFileNewCase;

  const _EmptyState({this.onFileNewCase});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined,
                size: 44, color: WarRoomTheme.muted),
            const SizedBox(height: 12),
            const Text(
              'No cases yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WarRoomTheme.dossierInk,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'When you file a case, it appears here with its '
              'severity band and status.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: WarRoomTheme.muted),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onFileNewCase,
              child: const Text('File a new case',
                  style: TextStyle(
                      color: WarRoomTheme.amber, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact date stamp, e.g. `3 Jul 2026` (locale-independent).
String _fmtDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
