import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/state/data/local_ledger_review_bloc.dart';
import 'package:civic_commons/state/ui/peer_review_queue_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerPost _post({
  required String id,
  int verifiedReviewers = 0,
  LedgerPostStatus status = LedgerPostStatus.peerReview,
  required DateTime createdAt,
}) =>
    LedgerPost(
      id: id,
      category: LedgerCategory.civicInfrastructure,
      pinCode: '800001',
      headline: 'Road repair tender delayed $id',
      body: 'Body $id',
      authorHandle: 'handle_$id',
      verifiedReviewers: verifiedReviewers,
      status: status,
      createdAt: createdAt,
    );

void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);

  Future<LocalLedgerReviewBloc> pumpSection(
    WidgetTester tester, {
    required InMemoryLedgerFeedRepository repo,
  }) async {
    final bloc = LocalLedgerReviewBloc(repository: repo);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PeerReviewQueueSection(bloc: bloc, pinCode: '800001'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  testWidgets('renders the review card with N/3 indicator (Task 7.6)',
      (tester) async {
    final repo = InMemoryLedgerFeedRepository(
      seed: [_post(id: 'a', verifiedReviewers: 1, createdAt: t0)],
    );
    final bloc = await pumpSection(tester, repo: repo);

    expect(find.text('PEER REVIEW GATE'), findsOneWidget);
    expect(find.text('Road repair tender delayed a'), findsOneWidget);
    expect(find.textContaining('1/3 approved'), findsOneWidget);
    expect(find.text('APPROVE'), findsOneWidget);
    expect(find.text('REJECT'), findsOneWidget);
    expect(find.text('FLAG'), findsOneWidget);
    // Blinded reviewer handles are rendered, never raw hashes.
    expect(find.textContaining('reviewer_'), findsWidgets);

    await bloc.close();
  });

  testWidgets('shows the PUBLISHED indicator at 3/3 consensus', (tester) async {
    final repo = InMemoryLedgerFeedRepository(
      seed: [_post(id: 'a', verifiedReviewers: 3, createdAt: t0)],
    );
    final bloc = await pumpSection(tester, repo: repo);

    expect(find.textContaining('3/3 — PUBLISHED'), findsOneWidget);
    // Controls are hidden once the gate has passed.
    expect(find.text('APPROVE'), findsNothing);

    await bloc.close();
  });

  testWidgets('approve action drives the decision through the bloc',
      (tester) async {
    final repo = InMemoryLedgerFeedRepository(
      seed: [_post(id: 'a', verifiedReviewers: 2, createdAt: t0)],
    );
    final bloc = await pumpSection(tester, repo: repo);

    await tester.tap(find.text('APPROVE'));
    await tester.pumpAndSettle();

    // 3rd approval -> consensus -> the post publishes and leaves the
    // review queue entirely (the section empties).
    expect((await repo.getById('a'))!.verifiedReviewers, 3);
    expect((await repo.getById('a'))!.status, LedgerPostStatus.published);
    expect(find.text('PEER REVIEW GATE'), findsNothing);
    expect(find.text('APPROVE'), findsNothing);

    await bloc.close();
  });

  testWidgets('reject action records but leaves the card awaiting review',
      (tester) async {
    final repo = InMemoryLedgerFeedRepository(
      seed: [_post(id: 'a', verifiedReviewers: 1, createdAt: t0)],
    );
    final bloc = await pumpSection(tester, repo: repo);

    await tester.tap(find.text('REJECT'));
    await tester.pumpAndSettle();

    // Still in review, still 1/3, but now marked REVIEWED by me.
    expect((await repo.getById('a'))!.verifiedReviewers, 1);
    expect((await repo.getById('a'))!.status, LedgerPostStatus.peerReview);
    expect(find.text('REVIEWED'), findsOneWidget);
    expect(find.text('APPROVE'), findsNothing); // controls hidden after review

    await bloc.close();
  });

  testWidgets('shows the shadow-queue teaser when shadow posts exist',
      (tester) async {
    final repo = InMemoryLedgerFeedRepository(
      seed: [
        _post(id: 'a', createdAt: t0),
        _post(id: 's', status: LedgerPostStatus.shadowQueue, createdAt: t0),
      ],
    );
    final bloc = await pumpSection(tester, repo: repo);

    expect(find.textContaining('1 post in the Shadow Queue'), findsOneWidget);

    await bloc.close();
  });

  testWidgets('renders NO PII or hash-shaped literals', (tester) async {
    final repo = InMemoryLedgerFeedRepository(
      seed: [
        _post(
          id: 'a',
          createdAt: t0,
        ),
      ],
    );
    // Deliberately hash-shaped author handle to prove the UI blinds it.
    repo.seed([
      LedgerPost(
        id: 'a',
        category: LedgerCategory.civicInfrastructure,
        pinCode: '800001',
        headline: 'H',
        body: 'B',
        authorHandle:
            'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2',
        verifiedReviewers: 1,
        status: LedgerPostStatus.peerReview,
        createdAt: t0,
      ),
    ]);
    final bloc = LocalLedgerReviewBloc(repository: repo);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PeerReviewQueueSection(bloc: bloc, pinCode: '800001'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No 64-hex hash can appear anywhere in the tree.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' | ');
    expect(RegExp(r'[0-9a-f]{64}').hasMatch(texts), isFalse);
    expect(texts.contains('+91'), isFalse);

    await bloc.close();
  });
}
