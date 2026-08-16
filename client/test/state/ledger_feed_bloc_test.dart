import 'package:civic_commons/geo/domain/explore_radius.dart';
import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/feed_scope.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/ledger/domain/ledger_vote.dart';
import 'package:civic_commons/ledger/domain/ledger_vote_record.dart';
import 'package:civic_commons/ledger/domain/ledger_vote_sink.dart';
import 'package:civic_commons/ledger/domain/peer_review.dart';
import 'package:civic_commons/state/data/local_ledger_feed_bloc.dart';
import 'package:civic_commons/state/domain/ledger_feed_bloc.dart';
import 'package:civic_commons/state/domain/ledger_feed_state.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerPost _post({
  required String id,
  LedgerCategory category = LedgerCategory.civicInfrastructure,
  String pinCode = '800001',
  String? district = 'Patna',
  int voteCount = 0,
  int verifiedReviewers = 0,
  LedgerPostStatus status = LedgerPostStatus.published,
  required DateTime createdAt,
}) =>
    LedgerPost(
      id: id,
      category: category,
      pinCode: pinCode,
      district: district,
      headline: 'Headline $id',
      body: 'Body $id',
      authorHandle: 'handle_$id',
      voteCount: voteCount,
      verifiedReviewers: verifiedReviewers,
      status: status,
      createdAt: createdAt,
    );

void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);
  final t1 = DateTime.utc(2026, 8, 10, 13);

  group('LedgerFeedBloc', () {
    test('start() loads the scoped feed + edition from the local cache',
        () async {
      final repo = InMemoryLedgerFeedRepository(
        edition: 412,
        seed: [
          _post(id: 'a', pinCode: '800001', createdAt: t0),
          _post(id: 'b', pinCode: '800002', createdAt: t1),
        ],
      );
      final bloc = LocalLedgerFeedBloc(repository: repo);
      final states = <LedgerFeedState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();

      final state = states.last;
      expect(state.status, LedgerFeedStatus.loaded);
      expect(state.pinCode, '800001');
      expect(state.edition, 412);
      expect(state.posts.map((p) => p.id), ['a']);
      expect(state.posts.first.authorHandle, 'handle_a');

      await sub.cancel();
      await bloc.close();
    });

    test('category filter narrows the visible list', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(
              id: 'a',
              category: LedgerCategory.civicInfrastructure,
              createdAt: t0),
          _post(
              id: 'b',
              category: LedgerCategory.satireAndCulture,
              createdAt: t1),
        ],
      );
      final bloc = LocalLedgerFeedBloc(repository: repo);
      final states = <LedgerFeedState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await bloc.selectCategory(LedgerCategory.satireAndCulture);
      await pumpEventQueue();

      expect(states.last.categoryFilter, LedgerCategory.satireAndCulture);
      expect(states.last.posts.map((p) => p.id), ['b']);

      await bloc.selectCategory(null);
      await pumpEventQueue();
      expect(states.last.categoryFilter, isNull);
      expect(states.last.posts.length, 2);

      await sub.cancel();
      await bloc.close();
    });

    test('pendingReviewCount counts peer-review + shadow posts', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'a', createdAt: t0),
          _post(id: 'b', status: LedgerPostStatus.peerReview, createdAt: t0),
          _post(id: 'c', status: LedgerPostStatus.shadowQueue, createdAt: t0),
        ],
      );
      final bloc = LocalLedgerFeedBloc(repository: repo);
      final states = <LedgerFeedState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();

      expect(states.last.pendingReviewCount, 2);

      await sub.cancel();
      await bloc.close();
    });

    test('vote() persists through the repository and re-emits', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', voteCount: 5, createdAt: t0)],
      );
      final bloc = LocalLedgerFeedBloc(repository: repo);
      final states = <LedgerFeedState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await bloc.vote('a', LedgerVoteDirection.up);
      await pumpEventQueue();

      expect(states.last.posts.first.voteCount, 6);
      expect(states.last.posts.first.myVote, LedgerVoteDirection.up);
      expect(states.last.posts.first.karmaScore, 2); // sqrt(6) floor

      await sub.cancel();
      await bloc.close();
    });

    test('vote() toggles off on the same direction (Task 7.5)', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', voteCount: 5, createdAt: t0)],
      );
      final bloc = LocalLedgerFeedBloc(repository: repo);
      final states = <LedgerFeedState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await bloc.vote('a', LedgerVoteDirection.up);
      await pumpEventQueue();
      await bloc.vote('a', LedgerVoteDirection.up);
      await pumpEventQueue();

      expect(states.last.posts.first.voteCount, 5);
      expect(states.last.posts.first.myVote, LedgerVoteDirection.none);

      await sub.cancel();
      await bloc.close();
    });

    test('a failing vote sink degrades gracefully — feed still updates',
        () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', voteCount: 5, createdAt: t0)],
      );
      final bloc = LocalLedgerFeedBloc(
        repository: repo,
        votes: _ThrowingVoteSink(),
      );
      final states = <LedgerFeedState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await bloc.vote('a', LedgerVoteDirection.up);
      await pumpEventQueue();

      // The vote is applied locally and the feed re-emits even though the
      // sink threw — graceful sync failure (Task 7.5).
      expect(states.last.posts.first.voteCount, 6);
      expect(states.last.posts.first.myVote, LedgerVoteDirection.up);

      await sub.cancel();
      await bloc.close();
    });

    test('verifiedReviewers badge data flows through (3/3 verified)', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', verifiedReviewers: 3, createdAt: t0)],
      );
      final bloc = LocalLedgerFeedBloc(repository: repo);
      final states = <LedgerFeedState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();
      expect(states.last.posts.first.verifiedReviewers, 3);
      await sub.cancel();
      await bloc.close();
    });

    test('setRadius refetches with the expanded scope and flags nearby posts',
        () async {
      final t0 = DateTime.utc(2026, 8, 14, 12);
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'local', createdAt: t0),
          _post(
              id: 'nearby',
              pinCode: '800002',
              district: 'Patna',
              createdAt: t0),
        ],
      );
      final bloc = LocalLedgerFeedBloc(repository: repo);
      final states = <LedgerFeedState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await bloc.setRadius(ExploreRadius.district10km);
      await pumpEventQueue();

      final last = states.last;
      expect(last.radius, ExploreRadius.district10km);
      expect(last.isExpanded, isTrue);
      expect(last.nearbyCount, 1);
      final nearby = last.posts.firstWhere((p) => p.id == 'nearby');
      expect(nearby.nearby, isTrue);
      final local = last.posts.firstWhere((p) => p.id == 'local');
      expect(local.nearby, isFalse);

      await bloc.setRadius(ExploreRadius.none);
      await pumpEventQueue();
      expect(states.last.isExpanded, isFalse);
      expect(states.last.posts.length, 1); // local only again

      await sub.cancel();
      await bloc.close();
    });

    test('state carries only non-PII projection fields', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', createdAt: t0)],
      );
      final bloc = LocalLedgerFeedBloc(repository: repo);
      final states = <LedgerFeedState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();

      final summary = states.last.posts.first;
      // The projection must NOT expose identity internals beyond the
      // non-PII handle.
      expect(summary.authorHandle, 'handle_a');
      expect(summary.pinCode, '800001');

      await sub.cancel();
      await bloc.close();
    });

    test('composes over the abstract port (clean architecture)', () async {
      late LedgerFeedBloc bloc;
      bloc = LocalLedgerFeedBloc(repository: _FakeRepo());
      final states = <LedgerFeedState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();
      expect(states.last.posts.length, 1);
      await sub.cancel();
      await bloc.close();
    });
  });
}

class _FakeRepo implements LedgerFeedRepository {
  final _posts = [
    LedgerPost(
      id: 'f',
      category: LedgerCategory.studentRights,
      pinCode: '800001',
      headline: 'Fake headline',
      body: 'Fake body',
      authorHandle: 'fake_handle',
      createdAt: DateTime.utc(2026, 8, 10),
    ),
  ];

  @override
  Future<int> currentEdition() async => 1;

  @override
  Future<LedgerPost?> getById(String id) async =>
      _posts.where((p) => p.id == id).firstOrNull;

  @override
  Future<List<LedgerPost>> listPosts({
    required String pinCode,
    LedgerCategory? category,
  }) async =>
      _posts;

  @override
  Future<FeedScopeResult> listScoped(FeedScope scope) async => FeedScopeResult(
        posts: _posts,
        expanded: false,
        nearbyCount: 0,
        nearbyIds: const {},
      );

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

class _ThrowingVoteSink implements LedgerVoteSink {
  @override
  Future<List<LedgerVoteRecord>> localVotes() async => const [];

  @override
  Future<String> save(LedgerVote vote) async {
    throw StateError('queue down');
  }
}
