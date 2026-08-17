import 'package:flutter/material.dart';

import '../../academy/data/academy_asset_catalog.dart';
import '../../academy/data/in_memory_video_room_source_resolver.dart';
import '../../academy/domain/academy_module.dart';
import '../../academy/domain/academy_video.dart';
import '../domain/academy_bloc.dart';
import '../domain/academy_offline_bloc.dart';
import '../domain/academy_state.dart';
import '../domain/sandbox_wiki_bloc.dart';
import '../domain/study_group_bloc.dart';
import 'academy_offline_section.dart';
import 'academy_sandbox_wiki_screen.dart';
import 'academy_study_group_screen.dart';
import 'academy_theme.dart';
import 'academy_video_room_player.dart';

/// The Academy module view screen (DESIGN.md §9.3, Phase 9 Task 9.1).
///
/// Task 9.3 ships the real VIDEO ROOM: the [VideoRoomPlayer] renders the
/// privacy-enhanced embed frame (validated YouTube id → `youtube-nocookie`
/// URL with `rel=0`, no autoplay, no recommendations, no Shorts) and plays
/// through the injected [VideoEmbedLauncher] seam. Task 9.4 ships the
/// OFFLINE COPY section (download-for-offline + storage warning) through
/// the optional [offlineBloc] seam. GUTENBERG ARCHIVE and SANDBOX remain
/// deferred placeholders (community surfaces).
///
/// SECURITY CHECKPOINT (Task 9.1 + 9.3): the screen renders ONLY public
/// course content — module title, duration, locale, the OPAQUE content
/// reference (never a raw URL), and a UUID-shortened module code. The video
/// surface imports NO video SDK: the embed URL is built only by
/// [PrivacyEmbedUrl.forSource] from a strictly validated video id.
class AcademyModuleScreen extends StatefulWidget {
  final AcademyBloc bloc;
  final AcademyModule module;

  /// The breadcrumb parent label, e.g. the domain title.
  final String? domainTitle;

  /// Fired when the completion toggle changes (host seam; the bloc already
  /// persists the toggle — this only enables UI-level acknowledgement).
  final ValueChanged<bool>? onCompletedChanged;

  /// Resolves the module's opaque content ref → validated video source.
  final VideoRoomSourceResolver videoSourceResolver;

  /// Plays the built privacy embed (production injects the platform
  /// launcher; the default is a no-op recorder for the harness/tests).
  final VideoEmbedLauncher videoLauncher;

  /// The offline-cache bloc (Task 9.4). When provided, the OFFLINE COPY
  /// section renders under the video room; production wiring injects the
  /// SQLCipher-backed [LocalAcademyOfflineBloc] at the Phase-9 composition
  /// root (the harness injects an in-memory one).
  final AcademyOfflineBloc? offlineBloc;

  /// The Sandbox Wiki bloc (Task 9.5). When provided, the SANDBOX section
  /// becomes tappable and opens the module-scoped wiki screen; production
  /// wiring injects the SQLCipher-backed bloc at the Phase-9 composition
  /// root (the harness injects an in-memory one).
  final SandboxWikiBloc? sandboxWikiBloc;

  /// The cross-pillar study group bloc (Task 9.6). When provided, the
  /// STUDY GROUPS section becomes tappable and opens the module-anchored
  /// matching screen (pin-code-based, blinded SG-#### handles only).
  final StudyGroupBloc? studyGroupBloc;

  /// The learner's coarse civic scope (6-digit PIN) used for study group
  /// matching (Task 9.6).
  final String? studyGroupPinCode;

  // NOTE: not const — the default resolver/launcher are runtime instances.
  AcademyModuleScreen({
    super.key,
    required this.bloc,
    required this.module,
    this.domainTitle,
    this.onCompletedChanged,
    this.offlineBloc,
    this.sandboxWikiBloc,
    this.studyGroupBloc,
    this.studyGroupPinCode,
    VideoRoomSourceResolver? videoSourceResolver,
    VideoEmbedLauncher? videoLauncher,
  })  : videoSourceResolver =
            videoSourceResolver ?? InMemoryVideoRoomSourceResolver(),
        videoLauncher = videoLauncher ?? NoopVideoEmbedLauncher();

  @override
  State<AcademyModuleScreen> createState() => _AcademyModuleScreenState();
}

class _AcademyModuleScreenState extends State<AcademyModuleScreen> {
  @override
  void initState() {
    super.initState();
    // Load the offline-cache snapshot once (the section late-subscribes to
    // the broadcast stream with a `current` fallback, so the snapshot is
    // never lost).
    widget.offlineBloc?.start();
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    return Scaffold(
      backgroundColor: AcademyTheme.paper,
      appBar: AppBar(
        backgroundColor: AcademyTheme.paper,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to syllabus',
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                _shortCode(module.moduleId),
                style: const TextStyle(
                  color: AcademyTheme.muted,
                  fontSize: 11,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Breadcrumb: Domain › Module title.
          Text(
            widget.domainTitle == null
                ? module.title
                : '${widget.domainTitle} › ${module.title}',
            style: const TextStyle(
              fontSize: 12,
              color: AcademyTheme.muted,
              fontFamily: AcademyTheme.monoFont,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            module.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AcademyTheme.ink,
              fontFamily: AcademyTheme.serifFont,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MetaChip(label: '${module.durationMinutes} min'),
              _MetaChip(label: module.locale.toUpperCase()),
              _MetaChip(
                  label: 'MOD-${_shortCode(module.moduleId).toUpperCase()}'),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AcademyTheme.rule),
          const SizedBox(height: 6),
          // Completion toggle (Task 9.1 progress tracking UI).
          StreamBuilder<AcademyState>(
            stream: widget.bloc.state,
            builder: (context, snapshot) {
              // Fall back to the bloc's latest emission when the broadcast
              // stream has not delivered yet (late subscriber) — same
              // late-subscribe treatment as the syllabus screen.
              final state = snapshot.data ?? widget.bloc.current;
              final completed =
                  state.completedModuleIds.contains(module.moduleId);
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: AcademyTheme.emerald,
                title: Text(
                  completed ? 'Module completed' : 'Mark as complete',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AcademyTheme.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  completed
                      ? 'Progress is saved on this device.'
                      : 'Progress is saved on this device only.',
                  style:
                      const TextStyle(fontSize: 12, color: AcademyTheme.muted),
                ),
                value: completed,
                onChanged: (v) async {
                  await widget.bloc.toggleModuleComplete(module.moduleId);
                  widget.onCompletedChanged?.call(v);
                },
              );
            },
          ),
          const Divider(color: AcademyTheme.rule),
          const SizedBox(height: 4),
          // VIDEO ROOM — the privacy-enhanced embed player (Task 9.3).
          VideoRoomPlayer(
            source: widget.videoSourceResolver.resolve(module.contentRef),
            launcher: widget.videoLauncher,
          ),
          // OFFLINE COPY — download-for-offline + storage warning (Task 9.4),
          // rendered when the composition root injects the offline bloc.
          if (widget.offlineBloc != null) ...[
            const SizedBox(height: 10),
            AcademyOfflineSection(
              bloc: widget.offlineBloc!,
              module: module,
              manifest: AcademyAssetCatalog.manifestFor(module),
              videoSource:
                  widget.videoSourceResolver.resolve(module.contentRef),
            ),
          ],
          const SizedBox(height: 10),
          // GUTENBERG ARCHIVE — OER resources (NCERT etc.).
          const _DeferredSection(
            icon: Icons.menu_book_rounded,
            title: 'GUTENBERG ARCHIVE',
            body: 'Open-education resources for this module are indexed '
                'with the Task 9.3 content delivery.',
          ),
          const SizedBox(height: 10),
          // SANDBOX — community notes (Task 9.5: the wiki screen opens when
          // the composition root injects the wiki bloc; otherwise the
          // deferred frame stays).
          if (widget.sandboxWikiBloc != null)
            _SandboxEntry(
              onTap: () => _openSandboxWiki(context),
            )
          else
            const _DeferredSection(
              icon: Icons.edit_note_rounded,
              title: 'SANDBOX',
              body: 'Community notes for this module open with the '
                  'Task 9.3 collaboration surface.',
            ),
          const SizedBox(height: 10),
          // STUDY GROUPS — cross-pillar matching (Task 9.6: the matching
          // screen opens when the composition root injects the bloc + the
          // learner's coarse pin scope; otherwise the deferred frame stays).
          if (widget.studyGroupBloc != null && widget.studyGroupPinCode != null)
            _StudyGroupEntry(
              onTap: () => _openStudyGroups(context),
            )
          else
            const _DeferredSection(
              icon: Icons.groups_rounded,
              title: 'STUDY GROUPS',
              body: 'Cross-pillar study groups for this module open with '
                  'the Task 9.6 matching surface.',
            ),
        ],
      ),
    );
  }

  void _openStudyGroups(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AcademyStudyGroupScreen(
          bloc: widget.studyGroupBloc!,
          module: widget.module,
          pinCode: widget.studyGroupPinCode!,
        ),
      ),
    );
  }

  void _openSandboxWiki(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AcademySandboxWikiScreen(
          bloc: widget.sandboxWikiBloc!,
          module: widget.module,
        ),
      ),
    );
  }

  /// First 8 hex chars of the UUID — a module CODE, never an identity.
  static String _shortCode(String moduleId) =>
      moduleId.length >= 8 ? moduleId.substring(0, 8) : moduleId;
}

class _MetaChip extends StatelessWidget {
  final String label;

  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AcademyTheme.surface,
        border: Border.all(color: AcademyTheme.rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: AcademyTheme.muted,
          fontFamily: AcademyTheme.monoFont,
        ),
      ),
    );
  }
}

/// The live STUDY GROUPS entry (Task 9.6) — tappable, opens the
/// module-anchored cross-pillar matching screen.
class _StudyGroupEntry extends StatelessWidget {
  final VoidCallback onTap;

  const _StudyGroupEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AcademyTheme.surface,
          border: Border.all(color: AcademyTheme.rule),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Row(
          children: [
            Icon(Icons.groups_rounded, size: 16, color: AcademyTheme.emerald),
            SizedBox(width: 8),
            Text(
              'STUDY GROUPS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AcademyTheme.ink,
                fontFamily: AcademyTheme.monoFont,
              ),
            ),
            Spacer(),
            Text(
              'FIND STUDY BUDDIES →',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AcademyTheme.emerald,
                fontFamily: AcademyTheme.monoFont,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The live SANDBOX entry (Task 9.5) — tappable, opens the module-scoped
/// Sandbox Wiki screen.
class _SandboxEntry extends StatelessWidget {
  final VoidCallback onTap;

  const _SandboxEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AcademyTheme.surface,
          border: Border.all(color: AcademyTheme.rule),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Row(
          children: [
            Icon(Icons.edit_note_rounded,
                size: 16, color: AcademyTheme.emerald),
            SizedBox(width: 8),
            Text(
              'SANDBOX',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AcademyTheme.ink,
                fontFamily: AcademyTheme.monoFont,
              ),
            ),
            Spacer(),
            Text(
              'COMMUNITY NOTES →',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AcademyTheme.emerald,
                fontFamily: AcademyTheme.monoFont,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A deferred section frame (archive — community surfaces land with the
/// Task 9.x collaboration work; VIDEO ROOM is real (9.3), SANDBOX is real
/// (9.5)).
class _DeferredSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _DeferredSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AcademyTheme.surface,
        border: Border.all(color: AcademyTheme.rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AcademyTheme.emerald),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AcademyTheme.ink,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              color: AcademyTheme.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
