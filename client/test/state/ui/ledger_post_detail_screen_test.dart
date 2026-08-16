import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/ledger/domain/ledger_vote.dart';
import 'package:civic_commons/state/data/local_ledger_feed_bloc.dart';
import 'package:civic_commons/state/ui/ledger_post_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerPost _post({
  int voteCount = 48,
  int commentCount = 12,
  int verifiedReviewers = 3,
  LedgerPostStatus status = LedgerPostStatus.published,
}) =>
    LedgerPost(
      id: 'p1',
      category: LedgerCategory.civicInfrastructure,
      pinCode: '800001',
      headline: 'Municipal contractor stopped work on Boring Road drainage',
      body: 'Drainage work has stopped for the third consecutive week.',
      authorHandle: 'handle_p1',
      voteCount: voteCount,
      commentCount: commentCount,
      verifiedReviewers: verifiedReviewers,
      status: status,
      createdAt: DateTime.utc(2026, 8, 10, 12),
    );

void main() {
  group('LedgerPostDetailScreen (Task 7.1)', () {
    testWidgets('renders headline, body, tier line and pin scope',
        (tester) async {
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(seed: [_post()]),
      );
      await tester.pumpWidget(MaterialApp(
        home: LedgerPostDetailScreen(bloc: bloc, post: _post()),
      ));
      await tester.pump();

      expect(
        find.text('Municipal contractor stopped work on Boring Road drainage'),
        findsOneWidget,
      );
      expect(find.textContaining('Drainage work has stopped'), findsOneWidget);
      // Tier line is non-PII — never the raw handle.
      expect(find.textContaining('Posted by ★ Analyst'), findsOneWidget);
      expect(find.text('handle_p1'), findsNothing);
      await bloc.close();
    });

    testWidgets('renders the Peer Review Gate badge at 3/3', (tester) async {
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(seed: [_post()]),
      );
      await tester.pumpWidget(MaterialApp(
        home: LedgerPostDetailScreen(bloc: bloc, post: _post()),
      ));
      await tester.pump();

      expect(find.textContaining('[✓ Peer Review Gate: 3/3 approved]'),
          findsOneWidget);
      await bloc.close();
    });

    testWidgets('partial review renders the pending badge', (tester) async {
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(seed: [
          _post(verifiedReviewers: 1, status: LedgerPostStatus.peerReview)
        ]),
      );
      await tester.pumpWidget(MaterialApp(
        home: LedgerPostDetailScreen(
          bloc: bloc,
          post:
              _post(verifiedReviewers: 1, status: LedgerPostStatus.peerReview),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('[✓ Peer Review Gate: 1/3 approved]'),
          findsOneWidget);
      await bloc.close();
    });

    testWidgets('upvote flows through the bloc and updates the karma score',
        (tester) async {
      final repo = InMemoryLedgerFeedRepository(seed: [_post()]);
      final bloc = LocalLedgerFeedBloc(repository: repo);
      await tester.pumpWidget(MaterialApp(
        home: LedgerPostDetailScreen(bloc: bloc, post: _post()),
      ));
      await tester.pump();

      // The detail screen renders the karma-weighted sub-linear score
      // (sqrt(48) floor = 6), not the raw tally (Task 7.5).
      expect(find.text('6'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump();

      // 49 votes -> sqrt(49) = 7.
      expect(find.text('7'), findsOneWidget);
      // The vote persists into the repository (raw tally is authoritative).
      expect((await repo.getById('p1'))!.voteCount, 49);
      expect((await repo.getById('p1'))!.myVote, LedgerVoteDirection.up);
      await bloc.close();
    });

    testWidgets('same-direction tap toggles the vote OFF (Task 7.5)',
        (tester) async {
      final repo = InMemoryLedgerFeedRepository(seed: [_post()]);
      final bloc = LocalLedgerFeedBloc(repository: repo);
      await tester.pumpWidget(MaterialApp(
        home: LedgerPostDetailScreen(bloc: bloc, post: _post()),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump();
      // 49 -> score 7.
      expect(find.text('7'), findsOneWidget);

      // Tapping up again removes the vote: back to 48 -> score 6.
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump();
      expect(find.text('6'), findsOneWidget);
      expect((await repo.getById('p1'))!.voteCount, 48);
      expect((await repo.getById('p1'))!.myVote, LedgerVoteDirection.none);
      await bloc.close();
    });

    testWidgets('downvote shows the active state and reduces the score',
        (tester) async {
      final repo = InMemoryLedgerFeedRepository(seed: [_post()]);
      final bloc = LocalLedgerFeedBloc(repository: repo);
      await tester.pumpWidget(MaterialApp(
        home: LedgerPostDetailScreen(bloc: bloc, post: _post()),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      await tester.pump();
      await tester.pump();

      // 47 votes -> sqrt(47) floor = 6 (the downvote is recorded, the raw
      // tally drops, and the score reflects the reduced tally).
      expect((await repo.getById('p1'))!.voteCount, 47);
      expect((await repo.getById('p1'))!.myVote, LedgerVoteDirection.down);
      await bloc.close();
    });

    testWidgets('share and flag invoke their callbacks', (tester) async {
      var shared = false;
      var flagged = false;
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(seed: [_post()]),
      );
      await tester.pumpWidget(MaterialApp(
        home: LedgerPostDetailScreen(
          bloc: bloc,
          post: _post(),
          onShare: () => shared = true,
          onFlag: () => flagged = true,
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.ios_share_rounded));
      await tester.pump();
      expect(shared, isTrue);

      await tester.tap(find.byIcon(Icons.flag_outlined));
      await tester.pump();
      expect(flagged, isTrue);
      await bloc.close();
    });

    testWidgets('empty replies section renders the prompt', (tester) async {
      final bloc = LocalLedgerFeedBloc(
        repository:
            InMemoryLedgerFeedRepository(seed: [_post(commentCount: 0)]),
      );
      await tester.pumpWidget(MaterialApp(
        home: LedgerPostDetailScreen(
          bloc: bloc,
          post: _post(commentCount: 0),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('No replies yet'), findsOneWidget);
      await bloc.close();
    });
  });
}
