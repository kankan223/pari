import 'dart:async';

import 'package:flutter/material.dart';

import '../../academy/domain/academy_module.dart';
import '../../academy/domain/academy_progress.dart';
import '../domain/academy_bloc.dart';
import '../domain/academy_state.dart';
import 'academy_masthead.dart';
import 'academy_theme.dart';

/// The Academy syllabus tree screen (DESIGN.md §9.2, Phase 9 Task 9.1).
///
/// Consumes the [AcademyBloc] state stream ONLY (clean architecture — no
/// repository/store access from the widget tree). Renders:
/// - the [AcademyMasthead] (textbook stamp bar + module count),
/// - the MY PROGRESS section: overall percent + per-domain completion
///   bars (deterministic projections, Task 9.1),
/// - the BROWSE BY DOMAIN grid: one card per domain (module count,
///   progress), each opening its module list,
/// - a domain module list with duration + locale + completion marker.
///
/// SECURITY CHECKPOINT (Task 9.1): the screen renders ONLY public course
/// content — domain/module titles, UUID-shortened module codes, duration
/// and locale tags. No phones, no names, no hashes, no user identity ever
/// reaches the tree.
class AcademySyllabusScreen extends StatefulWidget {
  final AcademyBloc bloc;

  /// Opens a module detail screen for [moduleId].
  final ValueChanged<String>? onModuleTap;

  const AcademySyllabusScreen(
      {super.key, required this.bloc, this.onModuleTap});

  @override
  State<AcademySyllabusScreen> createState() => _AcademySyllabusScreenState();
}

class _AcademySyllabusScreenState extends State<AcademySyllabusScreen> {
  /// Domain id of the expanded module list, or null to show the grid.
  String? _openDomain;

  @override
  void initState() {
    super.initState();
    // Re-emit on mount so a late StreamBuilder subscriber (broadcast
    // stream, no replay) always sees the latest state — the same
    // late-subscribe treatment as WarRoomCaseListScreen / LedgerFeedScreen.
    unawaited(widget.bloc.start());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AcademyTheme.paper,
      body: Column(
        children: [
          // The masthead's SecureScreenWrapper uses an Expanded internally,
          // so it needs bounded height — a Flexible(Fit.loose) sibling.
          const Flexible(
            fit: FlexFit.loose,
            child: AcademyMasthead(label: 'Browse curriculum'),
          ),
          Expanded(
            child: StreamBuilder<AcademyState>(
              stream: widget.bloc.state,
              builder: (context, snapshot) {
                final state = snapshot.data;
                if (state == null || state.phase == AcademyPhase.loading) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AcademyTheme.emerald,
                    ),
                  );
                }
                if (state.phase == AcademyPhase.failure) {
                  return _FailureView(onRetry: () => widget.bloc.retry());
                }
                final syllabus = state.syllabus;
                if (syllabus == null || syllabus.modules.isEmpty) {
                  return const Center(
                    child: Text(
                      'No curriculum yet.',
                      style: TextStyle(color: AcademyTheme.muted),
                    ),
                  );
                }
                return _buildReady(context, state);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReady(BuildContext context, AcademyState state) {
    final syllabus = state.syllabus!;
    final openDomain = _openDomain;
    final domain = openDomain == null
        ? null
        : syllabus.domains.firstWhere(
            (d) => d.domainId == openDomain,
            orElse: () => syllabus.domains.first,
          );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // MY PROGRESS (Task 9.1 progress tracking UI).
        _ProgressSection(syllabus: syllabus, state: state),
        const SizedBox(height: 8),
        if (domain == null) ...[
          const _SectionHeader('BROWSE BY DOMAIN'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [
              for (final d in syllabus.domains)
                _DomainCard(
                  domain: d,
                  modules: syllabus.modulesFor(d.domainId),
                  completed: state.completedModuleIds,
                  onTap: () => setState(() => _openDomain = d.domainId),
                ),
            ],
          ),
        ] else ...[
          // Module list for the opened domain.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _openDomain = null),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('All domains'),
                  style: TextButton.styleFrom(
                    foregroundColor: AcademyTheme.emerald,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const Spacer(),
                Text(
                  '${domain.title.toUpperCase()} · '
                  '${syllabus.modulesFor(domain.domainId).length} modules',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AcademyTheme.muted,
                    fontFamily: AcademyTheme.monoFont,
                  ),
                ),
              ],
            ),
          ),
          for (final m in syllabus.modulesFor(domain.domainId))
            _ModuleTile(
              module: m,
              completed: state.completedModuleIds.contains(m.moduleId),
              onTap: widget.onModuleTap == null
                  ? null
                  : () => widget.onModuleTap!(m.moduleId),
            ),
        ],
      ],
    );
  }
}

/// MY PROGRESS — overall bar + one row per domain (Task 9.1).
class _ProgressSection extends StatelessWidget {
  final AcademySyllabus syllabus;
  final AcademyState state;

  const _ProgressSection({required this.syllabus, required this.state});

  @override
  Widget build(BuildContext context) {
    final overall = AcademyProgress.overallPercent(
      syllabus: syllabus,
      completedModuleIds: state.completedModuleIds,
    );
    final done = state.completedModuleIds.length;
    final total = syllabus.moduleCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AcademyTheme.surface,
        border: Border.all(color: AcademyTheme.rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MY PROGRESS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AcademyTheme.emerald,
              fontFamily: AcademyTheme.monoFont,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: overall / 100,
                  minHeight: 6,
                  backgroundColor: AcademyTheme.rule,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AcademyTheme.emerald),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$overall% · $done/$total modules',
                style: const TextStyle(
                  fontSize: 12,
                  color: AcademyTheme.muted,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final d in syllabus.domains) ...[
            const SizedBox(height: 4),
            _DomainProgressRow(
              title: d.title,
              fraction: AcademyProgress.domainFraction(
                modules: syllabus.modulesFor(d.domainId),
                completedModuleIds: state.completedModuleIds,
              ),
              done: syllabus
                  .modulesFor(d.domainId)
                  .where((m) => state.completedModuleIds.contains(m.moduleId))
                  .length,
              total: syllabus.modulesFor(d.domainId).length,
            ),
          ],
        ],
      ),
    );
  }
}

class _DomainProgressRow extends StatelessWidget {
  final String title;
  final double fraction;
  final int done;
  final int total;

  const _DomainProgressRow({
    required this.title,
    required this.fraction,
    required this.done,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AcademyTheme.ink),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 4,
            backgroundColor: AcademyTheme.rule,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AcademyTheme.emerald),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            '$done/$total',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11,
              color: AcademyTheme.muted,
              fontFamily: AcademyTheme.monoFont,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AcademyTheme.emerald,
          fontFamily: AcademyTheme.monoFont,
        ),
      ),
    );
  }
}

/// One BROWSE BY DOMAIN card: title, module count, completion bar.
class _DomainCard extends StatelessWidget {
  final AcademyDomain domain;
  final List<AcademyModule> modules;
  final Set<String> completed;
  final VoidCallback onTap;

  const _DomainCard({
    required this.domain,
    required this.modules,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final percent = AcademyProgress.domainPercent(
      modules: modules,
      completedModuleIds: completed,
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AcademyTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: const BorderSide(color: AcademyTheme.rule),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                domain.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AcademyTheme.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${modules.length} modules · $percent%',
                style: const TextStyle(
                  fontSize: 11,
                  color: AcademyTheme.muted,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 4,
                  backgroundColor: AcademyTheme.rule,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AcademyTheme.emerald),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One module row inside a domain list.
class _ModuleTile extends StatelessWidget {
  final AcademyModule module;
  final bool completed;
  final VoidCallback? onTap;

  const _ModuleTile({
    required this.module,
    required this.completed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      elevation: 0,
      color: AcademyTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: const BorderSide(color: AcademyTheme.rule),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: Icon(
          completed ? Icons.check_circle_rounded : Icons.menu_book_rounded,
          color: completed ? AcademyTheme.emerald : AcademyTheme.muted,
        ),
        title: Text(
          module.title,
          style: const TextStyle(fontSize: 14, color: AcademyTheme.ink),
        ),
        subtitle: Text(
          '${module.durationMinutes} min · ${module.locale}',
          style: const TextStyle(
            fontSize: 11,
            color: AcademyTheme.muted,
            fontFamily: AcademyTheme.monoFont,
          ),
        ),
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_right_rounded,
                color: AcademyTheme.muted),
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  final VoidCallback onRetry;

  const _FailureView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded,
                size: 40, color: AcademyTheme.muted),
            const SizedBox(height: 10),
            const Text(
              'Unable to load the syllabus.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AcademyTheme.ink,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: AcademyTheme.emerald,
                side: const BorderSide(color: AcademyTheme.emerald),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
