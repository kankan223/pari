import 'dart:typed_data';

import 'package:civic_commons/academy/data/in_memory_academy_progress_store.dart';
import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/data/in_memory_module_download_dispatcher.dart';
import 'package:civic_commons/academy/data/in_memory_module_downloader.dart';
import 'package:civic_commons/academy/data/in_memory_offline_module_cache.dart';
import 'package:civic_commons/academy/data/in_memory_sandbox_wiki_repository.dart';
import 'package:civic_commons/academy/data/in_memory_study_group_repository.dart';
import 'package:civic_commons/academy/data/in_memory_video_room_source_resolver.dart';
import 'package:civic_commons/academy/domain/sandbox_wiki.dart';
import 'package:civic_commons/academy/domain/study_group.dart';
import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:civic_commons/state/data/local_academy_bloc.dart';
import 'package:civic_commons/state/data/local_academy_offline_bloc.dart';
import 'package:civic_commons/state/data/local_sandbox_wiki_bloc.dart';
import 'package:civic_commons/state/data/local_study_group_bloc.dart';
import 'package:civic_commons/state/ui/academy_module_screen.dart';
import 'package:civic_commons/state/ui/academy_sandbox_wiki_screen.dart';
import 'package:civic_commons/state/ui/academy_study_group_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final seed = InMemoryAcademySyllabusRepository.seedSyllabus;
  final module = seed.modulesFor('civics').first;

  Future<LocalAcademyBloc> readyBloc(WidgetTester tester,
      {Set<String>? completed}) async {
    final store = InMemoryAcademyProgressStore();
    for (final id in completed ?? const <String>{}) {
      await store.markModuleComplete(id);
    }
    final bloc = LocalAcademyBloc(
      repository: InMemoryAcademySyllabusRepository(),
      store: store,
    );
    // start() does real async work — run outside the FakeAsync zone.
    await tester.runAsync(bloc.start);
    await tester.pump();
    return bloc;
  }

  testWidgets('renders breadcrumb, metadata chips and module code',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyModuleScreen(
        bloc: bloc,
        module: module,
        domainTitle: 'Civic Education',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Civic Education › Fundamentals of Civic Rights'),
        findsOneWidget);
    expect(find.text('18 min'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
    // UUID-shortened module code (8 hex chars), never the full hash.
    expect(find.text('MOD-3F2504E0'), findsOneWidget);
    expect(find.textContaining('3f2504e0-4f89'), findsNothing);
  });

  testWidgets('completion toggle marks the module complete through the bloc',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyModuleScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Mark as complete'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Module completed'), findsOneWidget);
    expect(bloc.current.completedModuleIds, contains(module.moduleId));
  });

  testWidgets('pre-completed module shows completed state and can unmark',
      (tester) async {
    final bloc = await readyBloc(tester, completed: {module.moduleId});
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyModuleScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Module completed'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Mark as complete'), findsOneWidget);
    expect(bloc.current.completedModuleIds, isNot(contains(module.moduleId)));
  });

  testWidgets(
      'renders the real VIDEO ROOM player + deferred archive, '
      'sandbox falls back to the deferred frame without a wiki bloc',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyModuleScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // VIDEO ROOM is REAL in Task 9.3: the player renders the privacy-embed
    // frame (module's content ref resolves through the default resolver).
    expect(find.text('VIDEO ROOM'), findsOneWidget);
    expect(find.text('PRIVACY EMBED'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    // GUTENBERG ARCHIVE remains deferred; SANDBOX shows the deferred frame
    // until the composition root injects the wiki bloc (Task 9.5).
    await tester.scrollUntilVisible(find.text('GUTENBERG ARCHIVE'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('GUTENBERG ARCHIVE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('SANDBOX'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('SANDBOX'), findsOneWidget);
    expect(find.textContaining('Task 9.3'), findsWidgets);
  });

  testWidgets(
      'SANDBOX entry opens the wiki screen when a wiki bloc is '
      'injected (Task 9.5)', (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    // Seed the sandbox with one page so the opened wiki screen has content.
    final wikiRepository = InMemorySandboxWikiRepository();
    await wikiRepository.submitRevision(
      pageId: null,
      moduleId: module.moduleId,
      title: 'Civic Rights Notes',
      bodyMarkdown: '# One',
      locale: 'en',
      authorHandle: SandboxAuthorHandle.forModule(module.moduleId),
    );
    final wikiBloc = LocalSandboxWikiBloc(repository: wikiRepository);
    addTearDown(wikiBloc.close);
    await tester.runAsync(() => wikiBloc.start(module.moduleId));

    await tester.pumpWidget(MaterialApp(
      home: AcademyModuleScreen(
        bloc: bloc,
        module: module,
        sandboxWikiBloc: wikiBloc,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // The live SANDBOX entry replaces the deferred frame.
    await tester.scrollUntilVisible(find.text('SANDBOX'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('SANDBOX'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AcademySandboxWikiScreen), findsOneWidget);
    expect(find.text('Civic Rights Notes'), findsOneWidget);
  });

  testWidgets(
      'STUDY GROUPS entry opens the matching screen when a bloc + pin '
      'are injected (Task 9.6)', (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    // Seed one group so the opened screen has a match to render.
    final groupRepository = InMemoryStudyGroupRepository();
    await groupRepository.seedGroup(
      moduleId: module.moduleId,
      title: 'Civic Rights Study Circle',
      locale: 'en',
      pinCode: '800001',
      topics: [
        StudyTopicRef.parse(
            pillar: StudyPillar.academy, topicId: module.moduleId),
      ],
      capacity: 6,
    );
    final groupBloc = LocalStudyGroupBloc(repository: groupRepository);
    addTearDown(groupBloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyModuleScreen(
        bloc: bloc,
        module: module,
        studyGroupBloc: groupBloc,
        studyGroupPinCode: '800001',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // The live STUDY GROUPS entry replaces the deferred frame.
    await tester.scrollUntilVisible(find.text('STUDY GROUPS'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('STUDY GROUPS'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AcademyStudyGroupScreen), findsOneWidget);
    expect(find.text('Civic Rights Study Circle'), findsWidgets);
    // Blinded handle renders — the full module UUID never does.
    final handle = StudyGroupHandle.forModule(module.moduleId);
    expect(find.textContaining(handle), findsOneWidget);
  });

  testWidgets('SECURITY: no full UUID, no PII, code is 8-hex only',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyModuleScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'[0-9a-f]{12,}').hasMatch(w.data ?? '')),
      findsNothing,
      reason: 'the 36-char UUID must never render — only its 8-hex code',
    );
  });

  testWidgets(
      'integration: OFFLINE COPY section downloads the module through '
      'the injected offline bloc (Task 9.4)', (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);
    // Real AES-256-GCM test cipher (fast, no Argon2id) + in-process
    // dispatcher — the full download flow runs deterministically.
    late final InMemoryOfflineModuleCache cache;
    cache = InMemoryOfflineModuleCache(
      downloader: SimulatedModuleDownloader(cipher: _TestCipher()),
      dispatcher: InProcessModuleDownloadDispatcher(
        handler: (id) => cache.processQueuedDownload(id),
        runImmediately: true,
      ),
    );
    final offlineBloc = LocalAcademyOfflineBloc(cache: cache);
    addTearDown(offlineBloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyModuleScreen(
        bloc: bloc,
        module: module,
        offlineBloc: offlineBloc,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // The OFFLINE COPY section renders under the video room (scroll down
    // to the download button itself so the tap is inside the viewport).
    await tester.scrollUntilVisible(find.text('DOWNLOAD FOR OFFLINE'), 120,
        scrollable: find.byType(Scrollable).first);
    // The section is tall — bring the button fully into the viewport.
    await tester.ensureVisible(find.text('DOWNLOAD FOR OFFLINE'));
    await tester.pump();
    expect(find.text('OFFLINE COPY'), findsOneWidget);
    expect(find.text('DOWNLOAD FOR OFFLINE'), findsOneWidget);

    await tester.tap(find.text('DOWNLOAD FOR OFFLINE'));
    await tester.pumpAndSettle();

    // The full screen flow drives the download to READY.
    expect(find.textContaining('Offline copy ready'), findsOneWidget);
    expect(find.text('REMOVE'), findsOneWidget);
  });

  testWidgets(
      'integration: module screen plays the privacy embed through '
      'the injected launcher (Task 9.3)', (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);
    // A recording launcher — the harness/test never opens a real surface.
    final launcher = NoopVideoEmbedLauncher();

    await tester.pumpWidget(MaterialApp(
      home: AcademyModuleScreen(
        bloc: bloc,
        module: module,
        videoLauncher: launcher,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // The module's opaque content ref resolves to a validated source.
    expect(find.text('PLAY'), findsOneWidget);
    expect(launcher.lastLaunched, isNull); // no auto-launch

    await tester.tap(find.text('PLAY'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(launcher.lastLaunched, isNotNull);
    expect(
        launcher.lastLaunched, startsWith('https://www.youtube-nocookie.com/'));
    expect(launcher.lastLaunched!.toLowerCase(), isNot(contains('autoplay')));
    // The full screen keeps its FLAG_SECURE wrapper via the masthead path
    // (masthead wrapper verified in its own suite; the module screen is
    // reached from the syllabus masthead in the navigation integration).
    expect(find.text('Opened in privacy-enhanced embed'), findsOneWidget);
  });
}

/// Tiny fake cipher for the module-screen integration (sealed bytes distinct
/// from plaintext, no Argon2id at widget-test time).
class _TestCipher implements QueuePayloadCipher {
  @override
  Future<Uint8List> seal(Uint8List plaintext) async =>
      Uint8List.fromList([...plaintext, 7]);

  @override
  Future<Uint8List> open(Uint8List sealed) async =>
      sealed.sublist(0, sealed.length - 1);
}
