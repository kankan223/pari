import 'dart:typed_data';

import 'package:civic_commons/academy/data/in_memory_module_download_dispatcher.dart';
import 'package:civic_commons/academy/data/in_memory_offline_module_cache.dart';
import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:civic_commons/academy/domain/module_asset_manifest.dart';
import 'package:civic_commons/academy/domain/offline_module_cache.dart';
import 'package:civic_commons/state/data/local_academy_offline_bloc.dart';
import 'package:civic_commons/state/ui/academy_offline_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

AcademyModule get _module => AcademyModule.parse(
      moduleId: _m1,
      domainId: 'civics',
      title: 'Fundamentals of Civic Rights',
      durationMinutes: 18,
      locale: 'en',
      contentRef: 'civics/rights-fundamentals/mod-01',
    );

/// Returns a TINY sealed payload regardless of the manifest budget — the
/// storage-warning tests use 300 MB manifests without allocating 300 MB.
class TinyDownloader implements ModuleDownloader {
  @override
  Future<Uint8List> downloadModuleContent(
          String moduleId, int totalBytes) async =>
      Uint8List.fromList([1, 2, 3]);
}

class FlakyDownloader implements ModuleDownloader {
  int remainingFailures;

  FlakyDownloader({this.remainingFailures = 1});

  @override
  Future<Uint8List> downloadModuleContent(
      String moduleId, int totalBytes) async {
    if (remainingFailures > 0) {
      remainingFailures--;
      throw StateError('network unavailable');
    }
    return Uint8List.fromList([1, 2, 3]);
  }
}

Future<LocalAcademyOfflineBloc> _bloc(
  WidgetTester tester, {
  required ModuleDownloader downloader,
  bool runImmediately = true,
}) async {
  late final InMemoryOfflineModuleCache cache;
  cache = InMemoryOfflineModuleCache(
    downloader: downloader,
    dispatcher: InProcessModuleDownloadDispatcher(
      handler: (id) => cache.processQueuedDownload(id),
      runImmediately: runImmediately,
    ),
  );
  final bloc = LocalAcademyOfflineBloc(cache: cache);
  await tester.runAsync(bloc.start);
  await tester.pump();
  return bloc;
}

Future<void> _pump(
  WidgetTester tester,
  LocalAcademyOfflineBloc bloc,
  ModuleAssetManifest manifest,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AcademyOfflineSection(
        bloc: bloc,
        module: _module,
        manifest: manifest,
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  final smallManifest = ModuleAssetManifest.generateFor(
    _module,
    sizes: {'civics/rights-fundamentals/mod-01': 24 * 1024},
  );
  final bigManifest = ModuleAssetManifest.generateFor(
    _module,
    sizes: {'civics/rights-fundamentals/mod-01': 300 * 1024 * 1024},
  );

  group('AcademyOfflineSection (Task 9.4 — download-for-offline)', () {
    testWidgets('initial state shows NOT DOWNLOADED + the manifest budget',
        (tester) async {
      final bloc = await _bloc(tester, downloader: TinyDownloader());
      addTearDown(bloc.close);
      await _pump(tester, bloc, smallManifest);

      expect(find.text('OFFLINE COPY'), findsOneWidget);
      expect(find.text('OFFLINE'), findsOneWidget); // status chip
      expect(find.text('Not downloaded · 24 KB'), findsOneWidget);
      expect(find.text('DOWNLOAD FOR OFFLINE'), findsOneWidget);
    });

    testWidgets('DOWNLOAD drives the flow to READY, then REMOVE clears it',
        (tester) async {
      final bloc = await _bloc(tester, downloader: TinyDownloader());
      addTearDown(bloc.close);
      await _pump(tester, bloc, smallManifest);

      await tester.tap(find.text('DOWNLOAD FOR OFFLINE'));
      await tester.pumpAndSettle();

      expect(find.text('Offline copy ready · 24 KB'), findsOneWidget);
      expect(find.text('SAVED'), findsOneWidget); // status chip
      expect(find.text('REMOVE'), findsOneWidget);

      await tester.tap(find.text('REMOVE'));
      await tester.pumpAndSettle();

      expect(find.text('Not downloaded · 24 KB'), findsOneWidget);
      expect(find.text('DOWNLOAD FOR OFFLINE'), findsOneWidget);
    });

    testWidgets(
        'STORAGE WARNING gate: oversized download asks first, '
        'CANCEL aborts, DOWNLOAD proceeds + persistent banner', (tester) async {
      final bloc = await _bloc(tester, downloader: TinyDownloader());
      addTearDown(bloc.close);
      await _pump(tester, bloc, bigManifest);

      await tester.tap(find.text('DOWNLOAD FOR OFFLINE'));
      await tester.pumpAndSettle();

      expect(find.text('STORAGE WARNING'), findsOneWidget);
      expect(find.textContaining('would exceed the offline budget'),
          findsOneWidget);

      // CANCEL aborts — nothing scheduled.
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(find.text('Not downloaded · 300 MB'), findsOneWidget);
      expect(bloc.current.entryFor(_m1), isNull);

      // DOWNLOAD proceeds past the gate.
      await tester.tap(find.text('DOWNLOAD FOR OFFLINE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DOWNLOAD')); // the dialog action
      await tester.pumpAndSettle();

      expect(find.text('Offline copy ready · 300 MB'), findsOneWidget);
      // Persistent storage warning banner (300 MB > 200 MB budget).
      expect(find.textContaining('over the storage budget'), findsOneWidget);
    });

    testWidgets('a failed download shows the FAILED state and RETRY recovers',
        (tester) async {
      final bloc = await _bloc(tester, downloader: FlakyDownloader());
      addTearDown(bloc.close);
      await _pump(tester, bloc, smallManifest);

      await tester.tap(find.text('DOWNLOAD FOR OFFLINE'));
      await tester.pumpAndSettle();

      expect(find.text('Offline copy failed to download.'), findsOneWidget);
      expect(find.text('FAILED'), findsOneWidget); // status chip

      await tester.tap(find.text('RETRY'));
      await tester.pumpAndSettle();

      expect(find.text('Offline copy ready · 24 KB'), findsOneWidget);
    });

    testWidgets('a queued (in-flight) download shows the PREPARING state',
        (tester) async {
      final bloc = await _bloc(tester,
          downloader: TinyDownloader(), runImmediately: false);
      addTearDown(bloc.close);
      await _pump(tester, bloc, smallManifest);

      await tester.tap(find.text('DOWNLOAD FOR OFFLINE'));
      await tester.pumpAndSettle();

      expect(find.text('Preparing offline copy…'), findsOneWidget);
      expect(find.text('PREPARING'), findsOneWidget); // status chip
      // No double-schedule while preparing: the button is gone.
      expect(find.text('DOWNLOAD FOR OFFLINE'), findsNothing);
    });

    testWidgets('SECURITY: no full UUID and no identity render in the tree',
        (tester) async {
      final bloc = await _bloc(tester, downloader: TinyDownloader());
      addTearDown(bloc.close);
      await _pump(tester, bloc, smallManifest);

      expect(
        find.byWidgetPredicate(
            (w) => w is Text && w.data != null && w.data!.contains(_m1)),
        findsNothing,
        reason: 'the 36-char UUID module id must never render',
      );
      // The section tree stays minimal: status labels + sizes only.
      expect(find.textContaining('3f2504e0'), findsNothing);
    });
  });
}
