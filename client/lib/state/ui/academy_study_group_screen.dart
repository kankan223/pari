import 'dart:async';

import 'package:flutter/material.dart';

import '../../academy/domain/academy_module.dart';
import '../../academy/domain/study_group.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/study_group_bloc.dart';
import '../domain/study_group_state.dart';
import 'academy_theme.dart';

/// The cross-pillar study group matching screen (Task 9.6).
///
/// Module-anchored group list with live title search/filter + the
/// deterministic pin-code-based MATCHES section (best groups for the
/// learner's coarse civic scope + module interests, blinded `SG-####`
/// participants only) + CREATE GROUP entry. Joining a group is a local-first
/// write that also enqueues the SEALED mutation for sync.
///
/// SECURITY CHECKPOINT (Task 9.6): the screen renders ONLY public group
/// titles, the coarse pin-code scope, topic refs, match scores and the
/// deterministic `SG-####` blinded participant handle — no identity, no PII,
/// no participant list beyond the local device's own membership. All state
/// flows through the injected [StudyGroupBloc]. Wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE) with the standard test seam.
class AcademyStudyGroupScreen extends StatefulWidget {
  final StudyGroupBloc bloc;
  final AcademyModule module;

  /// The learner's coarse civic scope (6-digit PIN) used for matching.
  final String pinCode;

  /// Injectable FLAG_SECURE service (test seam) — null uses production.
  final SecureFlagService? secureFlagService;

  const AcademyStudyGroupScreen({
    super.key,
    required this.bloc,
    required this.module,
    required this.pinCode,
    this.secureFlagService,
  });

  @override
  State<AcademyStudyGroupScreen> createState() =>
      _AcademyStudyGroupScreenState();
}

class _AcademyStudyGroupScreenState extends State<AcademyStudyGroupScreen> {
  @override
  void initState() {
    super.initState();
    widget.bloc.start(
      moduleId: widget.module.moduleId,
      pinCode: widget.pinCode,
      locale: widget.module.locale,
    );
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AcademyTheme.paper,
      appBar: AppBar(
        backgroundColor: AcademyTheme.paper,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to module',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          '❧ THE ACADEMY',
          style: TextStyle(
            color: AcademyTheme.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: AcademyTheme.serifFont,
            letterSpacing: 1.1,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _openCreate(context),
            style: TextButton.styleFrom(
              foregroundColor: AcademyTheme.emerald,
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text(
              'NEW',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: AcademyTheme.monoFont,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'STUDY GROUPS',
                style: TextStyle(
                  color: AcademyTheme.emerald,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: AcademyTheme.monoFont,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _secure(
        StreamBuilder<StudyGroupState>(
          stream: widget.bloc.state,
          builder: (context, snapshot) {
            // Late-subscribe fallback (broadcast stream does not replay).
            final state = snapshot.data ?? widget.bloc.current;
            if (state.phase == StudyGroupPhase.failure) {
              return _FailureView(
                onRetry: () => widget.bloc.retry(),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    '${widget.module.title} › STUDY GROUPS',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AcademyTheme.muted,
                      fontFamily: AcademyTheme.monoFont,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'You study as ${state.participantHandle} · '
                    'scope ${state.pinCode}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AcademyTheme.muted,
                    ),
                  ),
                ),
                // Deterministic pin-code-based matches (Task 9.6).
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    state.matches.isEmpty
                        ? 'MATCHES — no groups in your scope yet'
                        : 'MATCHES — best fit for your scope',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AcademyTheme.emerald,
                      fontFamily: AcademyTheme.monoFont,
                    ),
                  ),
                ),
                if (state.matches.isNotEmpty)
                  // The matches section is height-bounded + scrollable so it
                  // can never overflow the viewport (the group list below
                  // stays the primary scroll surface).
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 190),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        children: [
                          for (final match in state.matches.take(3))
                            _MatchCard(
                              match: match,
                              joined: state.hasJoined(match.group.groupId),
                              onJoin: () =>
                                  widget.bloc.joinGroup(match.group.groupId),
                            ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: TextField(
                    onChanged: widget.bloc.search,
                    style:
                        const TextStyle(fontSize: 13, color: AcademyTheme.ink),
                    decoration: InputDecoration(
                      hintText: 'Search groups…',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AcademyTheme.muted),
                      prefixIcon: const Icon(Icons.search_rounded,
                          size: 18, color: AcademyTheme.muted),
                      isDense: true,
                      filled: true,
                      fillColor: AcademyTheme.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: const BorderSide(color: AcademyTheme.rule),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: const BorderSide(color: AcademyTheme.rule),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: state.filteredGroups.isEmpty
                      ? _EmptyGroups(
                          hasQuery: state.query.trim().isNotEmpty,
                          onCreate: () => _openCreate(context),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                          itemCount: state.filteredGroups.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) => _groupCard(
                              context, state.filteredGroups[index], state),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _groupCard(
      BuildContext context, StudyGroup group, StudyGroupState state) {
    final joined = state.hasJoined(group.groupId);
    return InkWell(
      onTap: joined ? null : () => widget.bloc.joinGroup(group.groupId),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AcademyTheme.surface,
          border: Border.all(
              color: joined ? AcademyTheme.emerald : AcademyTheme.rule),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_rounded,
                    size: 16, color: AcademyTheme.emerald),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AcademyTheme.ink,
                    ),
                  ),
                ),
                Text(
                  '${group.participantCount}/${group.capacity}',
                  style:
                      const TextStyle(fontSize: 11, color: AcademyTheme.muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _topicChip('PIN ${group.pinCode}'),
                for (final t in group.topics) _topicChip(_topicLabel(t)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  joined ? '✓ You are in this group' : 'Tap to join',
                  style: TextStyle(
                    fontSize: 11,
                    color: joined ? AcademyTheme.emerald : AcademyTheme.muted,
                    fontWeight: joined ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                const Spacer(),
                if (!joined)
                  const Text(
                    'JOIN →',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AcademyTheme.emerald,
                      fontFamily: AcademyTheme.monoFont,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _topicChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AcademyTheme.paper,
        border: Border.all(color: AcademyTheme.rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: AcademyTheme.muted,
          fontFamily: AcademyTheme.monoFont,
        ),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CreateGroupSheet(
          bloc: widget.bloc,
          module: widget.module,
          pinCode: widget.pinCode,
          secureFlagService: widget.secureFlagService,
        ),
      ),
    );
  }
}

/// A deterministic match card — the group's score + its cross-pillar topic
/// chips (blinded handles only, zero PII).
class _MatchCard extends StatelessWidget {
  final StudyGroupMatch match;
  final bool joined;
  final VoidCallback onJoin;

  const _MatchCard({
    required this.match,
    required this.joined,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final group = match.group;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AcademyTheme.surface,
        border: Border.all(color: AcademyTheme.emerald, width: 1.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded,
                  size: 16, color: AcademyTheme.emerald),
              const SizedBox(width: 6),
              Text(
                'SCORE ${match.score}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AcademyTheme.emerald,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
              const Spacer(),
              Text(
                '${group.participantCount}/${group.capacity}',
                style: const TextStyle(fontSize: 11, color: AcademyTheme.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            group.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AcademyTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'PIN ${group.pinCode} · ${group.locale.toUpperCase()}',
            style: const TextStyle(fontSize: 11, color: AcademyTheme.muted),
          ),
          const SizedBox(height: 8),
          if (joined)
            const Text(
              '✓ Joined',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AcademyTheme.emerald,
              ),
            )
          else
            TextButton.icon(
              onPressed: onJoin,
              style: TextButton.styleFrom(
                foregroundColor: AcademyTheme.emerald,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
              ),
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text(
                'JOIN GROUP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Non-PII topic label for a cross-pillar ref — the pillar stamp + the
/// opaque topic id (UUID-shortened to 8 chars when it is a UUID).
String _topicLabel(StudyTopicRef t) {
  final pillar = switch (t.pillar) {
    StudyPillar.academy => 'ACAD',
    StudyPillar.ledger => 'LEDGER',
    StudyPillar.warRoom => 'WAR',
  };
  var id = t.topicId;
  if (id.length >= 8) {
    id = id.substring(0, 8);
  }
  return '$pillar-$id';
}

class _EmptyGroups extends StatelessWidget {
  final bool hasQuery;
  final VoidCallback onCreate;

  const _EmptyGroups({required this.hasQuery, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_rounded,
                size: 36, color: AcademyTheme.muted),
            const SizedBox(height: 10),
            Text(
              hasQuery
                  ? 'No groups match the search.'
                  : 'No study groups yet — start one for this module.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AcademyTheme.ink),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: AcademyTheme.emerald,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text(
                'CREATE GROUP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
            ),
          ],
        ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Unable to load study groups.',
            style: TextStyle(fontSize: 13, color: AcademyTheme.ink),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AcademyTheme.emerald,
            ),
            child: const Text('RETRY',
                style: TextStyle(fontFamily: AcademyTheme.monoFont)),
          ),
        ],
      ),
    );
  }
}

/// The CREATE GROUP sheet — public title, capacity and cross-pillar topic
/// refs (all non-PII; the anchor module + pin scope come from the screen).
class _CreateGroupSheet extends StatefulWidget {
  final StudyGroupBloc bloc;
  final AcademyModule module;
  final String pinCode;
  final SecureFlagService? secureFlagService;

  const _CreateGroupSheet({
    required this.bloc,
    required this.module,
    required this.pinCode,
    this.secureFlagService,
  });

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _capacity = TextEditingController(text: '5');
  final TextEditingController _topic = TextEditingController();
  bool _includeLedger = true;
  bool _includeWarRoom = true;

  @override
  void dispose() {
    _title.dispose();
    _capacity.dispose();
    _topic.dispose();
    super.dispose();
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final capacity = int.tryParse(_capacity.text.trim()) ?? 0;
    if (title.isEmpty || capacity < 2) {
      return; // simple validation — no harsh errors (trauma-informed UX).
    }
    final topics = <StudyTopicRef>[
      StudyTopicRef.parse(
        pillar: StudyPillar.academy,
        topicId: widget.module.moduleId,
      ),
    ];
    final extra = _topic.text.trim();
    if (extra.isNotEmpty) {
      final ref = StudyTopicRef.tryParse(
        pillar: StudyPillar.ledger,
        topicId: extra.toLowerCase(),
      );
      if (ref != null) {
        topics.add(ref);
      }
    }
    if (_includeLedger) {
      topics.add(StudyTopicRef.parse(
        pillar: StudyPillar.ledger,
        topicId: 'civics',
      ));
    }
    if (_includeWarRoom) {
      topics.add(StudyTopicRef.parse(
        pillar: StudyPillar.warRoom,
        topicId: 'osint',
      ));
    }
    await widget.bloc.createGroup(
      title: title,
      topics: topics,
      capacity: capacity,
    );
    if (mounted) {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AcademyTheme.paper,
      appBar: AppBar(
        backgroundColor: AcademyTheme.paper,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to study groups',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'CREATE GROUP',
          style: TextStyle(
            color: AcademyTheme.ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: AcademyTheme.monoFont,
            letterSpacing: 0.8,
          ),
        ),
      ),
      body: _secure(
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _title,
              style: const TextStyle(fontSize: 13, color: AcademyTheme.ink),
              decoration: _input('Group title (public)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13, color: AcademyTheme.ink),
              decoration: _input('Capacity (2–10)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _topic,
              style: const TextStyle(fontSize: 13, color: AcademyTheme.ink),
              decoration: _input('Extra topic slug (optional)'),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _includeLedger,
              onChanged: (v) => setState(() => _includeLedger = v ?? true),
              title: const Text(
                'Link a Ledger civic topic',
                style: TextStyle(fontSize: 12, color: AcademyTheme.ink),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _includeWarRoom,
              onChanged: (v) => setState(() => _includeWarRoom = v ?? true),
              title: const Text(
                'Link a War Room topic',
                style: TextStyle(fontSize: 12, color: AcademyTheme.ink),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This group is anchored on this module and matched by your '
              'coarse scope ${widget.pinCode}.',
              style: const TextStyle(fontSize: 11, color: AcademyTheme.muted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AcademyTheme.emerald,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'CREATE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: AcademyTheme.muted),
        isDense: true,
        filled: true,
        fillColor: AcademyTheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: AcademyTheme.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: AcademyTheme.rule),
        ),
      );
}
