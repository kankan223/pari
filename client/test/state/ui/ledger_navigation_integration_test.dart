import 'package:civic_commons/ledger/data/in_memory_ledger_draft_sink.dart';
import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/state/data/local_ledger_compose_bloc.dart';
import 'package:civic_commons/state/data/local_ledger_feed_bloc.dart';
import 'package:civic_commons/state/ui/ledger_compose_screen.dart';
import 'package:civic_commons/state/ui/ledger_feed_screen.dart';
import 'package:civic_commons/state/ui/ledger_post_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tall viewport so the full compose form (incl. the publish button) is
/// on-screen.
void _setTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Full navigation flow (Task 7.1): feed → post detail → compose, driven
/// by the real repositories + blocs (no fakes), mirroring the composition
/// root wiring.
void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);
  LedgerPost makePost(String id,
          {LedgerCategory category = LedgerCategory.breakingLocal}) =>
      LedgerPost(
        id: id,
        category: category,
        pinCode: '800001',
        headline: 'Water pipeline burst near Gandhi Maidan',
        body: 'Supply restored after 6 hours; report filed.',
        authorHandle: 'handle_$id',
        voteCount: 12,
        commentCount: 3,
        verifiedReviewers: 2,
        createdAt: t0,
      );

  testWidgets('feed → detail → compose round trip with real stores',
      (tester) async {
    final feedRepo =
        InMemoryLedgerFeedRepository(seed: [makePost('p1')], edition: 412);
    final draftSink = InMemoryLedgerDraftSink();
    final feedBloc = LocalLedgerFeedBloc(repository: feedRepo);
    final composeBloc = LocalLedgerComposeBloc(drafts: draftSink);

    // Stateful navigation shell: the composition root swaps the screen
    // based on the callback-driven navigation.
    Widget shell(Widget child) => MaterialApp(home: child);

    // --- Feed ---
    var openedPostId = '';
    var composing = false;
    await tester.pumpWidget(shell(
      LedgerFeedScreen(
        bloc: feedBloc,
        pinCode: '800001',
        onPostTap: (id) => openedPostId = id,
        onCompose: () => composing = true,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.text('THE DAILY LEDGER'), findsOneWidget);
    expect(find.text('EDITION 412 · 800001'), findsOneWidget);
    expect(
        find.text('Water pipeline burst near Gandhi Maidan'), findsOneWidget);

    // --- Feed → Detail ---
    final post = await feedRepo.getById('p1');
    expect(post, isNotNull);
    await tester.tap(find.text('Water pipeline burst near Gandhi Maidan'));
    await tester.pump();
    expect(openedPostId, 'p1');
    await tester.pumpWidget(shell(
      LedgerPostDetailScreen(bloc: feedBloc, post: post!),
    ));
    await tester.pump();
    expect(find.textContaining('Posted by ★'), findsOneWidget);
    expect(find.textContaining('[✓ Peer Review Gate: 2/3 approved]'),
        findsOneWidget);

    // Vote in detail → back to feed shows the updated aggregate.
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump();
    expect((await feedRepo.getById('p1'))!.voteCount, 13);

    // --- Detail → Compose (back to feed first, then FAB) ---
    await tester.pumpWidget(shell(
      LedgerFeedScreen(
        bloc: feedBloc,
        pinCode: '800001',
        onPostTap: (_) {},
        onCompose: () => composing = true,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(composing, isTrue);

    _setTallViewport(tester);
    await tester.pumpWidget(shell(
      LedgerComposeScreen(bloc: composeBloc, defaultPinCode: '800001'),
    ));
    await tester.pump();
    expect(find.text('New Post'), findsOneWidget);

    // Compose + publish a real draft.
    await tester.tap(find.byType(DropdownButtonFormField<LedgerCategory>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Satire & Culture').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'State the issue plainly'),
        'Councillor mixes up pothole map and bingo card');
    await tester.pump();
    await tester.tap(find.text('Publish — send to review'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(draftSink.saved, hasLength(1));
    expect(draftSink.saved.first.headline,
        'Councillor mixes up pothole map and bingo card');
    expect(draftSink.saved.first.category, LedgerCategory.satireAndCulture);

    await feedBloc.close();
    await composeBloc.close();
  });
}
