import 'dart:async';

import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/feed_scope.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/ledger/domain/ledger_vote.dart';
import 'package:civic_commons/ledger/domain/peer_review.dart';
import 'package:civic_commons/state/data/local_ledger_feed_bloc.dart';
import 'package:civic_commons/state/domain/ledger_feed_bloc.dart';
import 'package:civic_commons/state/ui/ledger_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerPost _post({
  required String id,
  String? headline,
  LedgerCategory category = LedgerCategory.civicInfrastructure,
  String pinCode = '800001',
  int voteCount = 0,
  int commentCount = 0,
  int verifiedReviewers = 0,
  LedgerPostStatus status = LedgerPostStatus.published,
  required DateTime createdAt,
}) =>
    LedgerPost(
      id: id,
      category: category,
      pinCode: pinCode,
      headline: headline ?? 'Headline $id',
      body: 'Body $id',
      authorHandle: 'handle_$id',
      voteCount: voteCount,
      commentCount: commentCount,
      verifiedReviewers: verifiedReviewers,
      status: status,
      createdAt: createdAt,
    );

Widget _wrap(LedgerFeedBloc bloc,
        {String pinCode = '800001',
        ValueChanged<String>? onPostTap,
        VoidCallback? onCompose,
        VoidCallback? onLoadOlder}) =>
    MaterialApp(
      home: LedgerFeedScreen(
        bloc: bloc,
        pinCode: pinCode,
        onPostTap: onPostTap,
        onCompose: onCompose,
        onLoadOlder: onLoadOlder,
      ),
    );

/// Pumps until the feed state lands (repo reads are async microtasks).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

/// Gated [LedgerFeedRepository] — listPosts waits until [gate] completes,
/// so the loading frame is deterministic in tests.
class _GatedRepo implements LedgerFeedRepository {
  _GatedRepo(this.gate);

  final Completer<void> gate;

  @override
  Future<int> currentEdition() async => 412;

  @override
  Future<LedgerPost?> getById(String id) async => null;

  @override
  Future<List<LedgerPost>> listPosts({
    required String pinCode,
    LedgerCategory? category,
  }) async {
    await gate.future;
    return const [];
  }

  @override
  Future<FeedScopeResult> listScoped(FeedScope scope) async {
    await gate.future;
    return const FeedScopeResult(
      posts: [],
      expanded: false,
      nearbyCount: 0,
      nearbyIds: {},
    );
  }

  @override
  Future<LedgerVoteDirection> vote(
      String id, LedgerVoteDirection direction) async {
    return direction;
  }

  @override
  Future<LedgerPostStatus> applyReview(
      String id, PeerReviewDecision decision) async {
    return LedgerPostStatus.peerReview;
  }
}

void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);

  group('LedgerFeedScreen (Task 7.1)', () {
    testWidgets('shows a loader before the feed loads', (tester) async {
      final gate = Completer<void>();
      final bloc = LocalLedgerFeedBloc(repository: _GatedRepo(gate));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      // Masthead renders immediately; body is a spinner until the state
      // lands.
      expect(find.text('THE DAILY LEDGER'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Release the gate — the feed lands and the spinner clears.
      gate.complete();
      await _settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await bloc.close();
    });

    testWidgets('renders post cards with non-PII author handles only',
        (tester) async {
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(
          seed: [
            _post(
                id: 'p1',
                headline: 'Boring Road drainage stopped again',
                createdAt: t0),
          ],
        ),
      );
      await tester.pumpWidget(_wrap(bloc));
      await _settle(tester);

      expect(find.text('Boring Road drainage stopped again'), findsOneWidget);
      expect(find.textContaining('handle_p1'), findsOneWidget);
      expect(find.text('#CIVIC INFRA'), findsWidgets);
      // No 64-hex blind hash anywhere in the tree.
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .any((t) => RegExp(r'[0-9a-f]{64}').hasMatch(t.data ?? '')),
        isFalse,
      );
      await bloc.close();
    });

    testWidgets('category filter chips render and re-filter on tap',
        (tester) async {
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(
          seed: [
            _post(
                id: 'p1',
                category: LedgerCategory.civicInfrastructure,
                createdAt: t0),
            _post(
                id: 'p2',
                category: LedgerCategory.satireAndCulture,
                createdAt: t0),
          ],
        ),
      );
      await tester.pumpWidget(_wrap(bloc));
      await _settle(tester);

      expect(find.text('ALL'), findsOneWidget);
      expect(find.text('#CIVIC INFRA'), findsWidgets);
      expect(find.text('#SATIRE'), findsWidgets);

      // Filter to Satire — only the satire post remains.
      await tester.tap(find.text('#SATIRE').first);
      await _settle(tester);
      expect(find.text('Headline p2'), findsOneWidget);
      expect(find.text('Headline p1'), findsNothing);
      await bloc.close();
    });

    testWidgets('peer review teaser shows the pending count', (tester) async {
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(
          seed: [
            _post(id: 'p1', createdAt: t0),
            _post(id: 'r1', status: LedgerPostStatus.peerReview, createdAt: t0),
            _post(
                id: 's1', status: LedgerPostStatus.shadowQueue, createdAt: t0),
          ],
        ),
      );
      await tester.pumpWidget(_wrap(bloc));
      await _settle(tester);

      // The teaser sits below the cards in the (lazy) ListView — scroll it
      // into view before asserting (cards are taller with the Task 7.5
      // vote bar).
      await tester.scrollUntilVisible(
        find.textContaining('2 posts in Peer Review'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.textContaining('2 posts in Peer Review'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('verified badge renders for 3/3 reviewed posts',
        (tester) async {
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(
          seed: [_post(id: 'p1', verifiedReviewers: 3, createdAt: t0)],
        ),
      );
      await tester.pumpWidget(_wrap(bloc));
      await _settle(tester);

      expect(find.textContaining('✓ Verified'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('load-older button + compose FAB invoke callbacks',
        (tester) async {
      var loadedOlder = false;
      var composed = false;
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(seed: []),
      );
      await tester.pumpWidget(_wrap(
        bloc,
        onLoadOlder: () => loadedOlder = true,
        onCompose: () => composed = true,
      ));
      await _settle(tester);

      await tester.ensureVisible(find.text('Load older posts'));
      await tester.pump();
      await tester.tap(find.text('Load older posts'));
      await tester.pump();
      expect(loadedOlder, isTrue);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      expect(composed, isTrue);
      await bloc.close();
    });

    testWidgets('tapping a post card invokes onPostTap with its id',
        (tester) async {
      String? opened;
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(
          seed: [_post(id: 'p1', createdAt: t0)],
        ),
      );
      await tester.pumpWidget(_wrap(bloc, onPostTap: (id) => opened = id));
      await _settle(tester);

      await tester.tap(find.text('Headline p1'));
      await tester.pump();
      expect(opened, 'p1');
      await bloc.close();
    });
  });
}
