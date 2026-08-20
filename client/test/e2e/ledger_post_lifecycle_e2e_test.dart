import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/feed_scope.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/ledger/domain/ledger_vote.dart';
import 'package:civic_commons/ledger/domain/peer_review.dart';
import 'package:civic_commons/geo/domain/explore_radius.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 13.3 E2E: Ledger pillar end-to-end lifecycle.
void main() {
  group('Ledger E2E - Post lifecycle through voting and peer review', () {
    late InMemoryLedgerFeedRepository repo;

    setUp(() {
      repo = InMemoryLedgerFeedRepository();
    });

    test('complete lifecycle: seed → vote → review → publish', () async {
      // Step 1: Seed the feed.
      final publishedPost = LedgerPost(
        id: 'post-published',
        category: LedgerCategory.breakingLocal,
        pinCode: '800001',
        headline: 'Road repair completed',
        body: 'The long-awaited road repair is done.',
        authorHandle: '@citizen-one',
        voteCount: 15,
        status: LedgerPostStatus.published,
        createdAt: DateTime(2026, 8, 15),
      );

      final reviewPost = LedgerPost(
        id: 'post-review',
        category: LedgerCategory.civicInfrastructure,
        pinCode: '800001',
        headline: 'New bus route proposed',
        body: 'A new bus route.',
        authorHandle: '@citizen-two',
        voteCount: 5,
        status: LedgerPostStatus.peerReview,
        createdAt: DateTime(2026, 8, 16),
      );

      final shadowPost = LedgerPost(
        id: 'post-shadow',
        category: LedgerCategory.consumerWatch,
        pinCode: '800001',
        headline: 'Price hike at market',
        body: 'Prices have risen.',
        authorHandle: '@citizen-three',
        voteCount: 2,
        verifiedReviewers: 1,
        status: LedgerPostStatus.shadowQueue,
        createdAt: DateTime(2026, 8, 17),
      );

      repo.seed([publishedPost, reviewPost, shadowPost]);

      // Step 2: Verify feed ordering: published first, then non-published
      // newest first. Order: published (8/15), shadow (8/17), review (8/16).
      final feed = await repo.listPosts(pinCode: '800001');
      expect(feed, hasLength(3));
      expect(feed.first.id, 'post-published');
      // Non-published sorted newest first: shadow (8/17), review (8/16)
      expect(feed[1].id, 'post-shadow');
      expect(feed[2].id, 'post-review');

      // Step 3: Vote on a published post.
      var voteResult =
          await repo.vote('post-published', LedgerVoteDirection.up);
      expect(voteResult, LedgerVoteDirection.up);
      expect((await repo.getById('post-published'))!.voteCount, 16);

      // Toggle off.
      voteResult = await repo.vote('post-published', LedgerVoteDirection.up);
      expect(voteResult, LedgerVoteDirection.none);
      expect((await repo.getById('post-published'))!.voteCount, 15);

      // Downvote.
      voteResult = await repo.vote('post-published', LedgerVoteDirection.down);
      expect(voteResult, LedgerVoteDirection.down);
      expect((await repo.getById('post-published'))!.voteCount, 14);

      // Step 4: Peer review gate — 3/3 → published.
      final s1 =
          await repo.applyReview('post-review', PeerReviewDecision.approved);
      expect(s1, LedgerPostStatus.peerReview);
      expect((await repo.getById('post-review'))!.verifiedReviewers, 1);

      final s2 =
          await repo.applyReview('post-review', PeerReviewDecision.approved);
      expect(s2, LedgerPostStatus.peerReview);
      expect((await repo.getById('post-review'))!.verifiedReviewers, 2);

      final s3 =
          await repo.applyReview('post-review', PeerReviewDecision.approved);
      expect(s3, LedgerPostStatus.published);
      final p3 = await repo.getById('post-review');
      expect(p3!.verifiedReviewers, 3);
      expect(p3.status, LedgerPostStatus.published);

      // Step 5: Immutability — late approval is a no-op.
      final s4 =
          await repo.applyReview('post-review', PeerReviewDecision.approved);
      expect(s4, LedgerPostStatus.published);
      expect((await repo.getById('post-review'))!.verifiedReviewers, 3);

      // Step 6: Rejection doesn't advance count.
      await repo.applyReview('post-shadow', PeerReviewDecision.rejected);
      expect((await repo.getById('post-shadow'))!.verifiedReviewers, 1);

      expect(await repo.currentEdition(), 412);
    });

    test('feed scope expansion with district radius', () async {
      final localPost = LedgerPost(
        id: 'local-1',
        category: LedgerCategory.breakingLocal,
        pinCode: '800001',
        district: 'Bangalore Urban',
        headline: 'Local event',
        body: 'A local event.',
        authorHandle: '@citizen-a',
        createdAt: DateTime(2026, 8, 18),
      );
      final nearbyPost = LedgerPost(
        id: 'nearby-1',
        category: LedgerCategory.breakingLocal,
        pinCode: '800002',
        district: 'Bangalore Urban',
        headline: 'Nearby event',
        body: 'A nearby event.',
        authorHandle: '@citizen-b',
        createdAt: DateTime(2026, 8, 18),
      );
      repo.seed([localPost, nearbyPost]);

      // Exact pin: only local-1.
      final feed = await repo.listPosts(pinCode: '800001');
      expect(feed, hasLength(1));
      expect(feed.first.id, 'local-1');

      // Scoped query with district radius (isExpanded=true) and low threshold.
      final feedResult = await repo.listScoped(
        FeedScope(
          pinCode: '800001',
          radius: ExploreRadius.district10km,
          expansionThreshold: 3,
          now: () => DateTime(2026, 8, 20),
        ),
      );
      expect(feedResult.posts.length, 2);
      expect(feedResult.expanded, isTrue);
      expect(feedResult.nearbyCount, 1);
      expect(feedResult.nearbyIds, contains('nearby-1'));
    });

    test('no PII leaks in feed', () async {
      repo.seed([
        LedgerPost(
          id: 'pii-check',
          category: LedgerCategory.breakingLocal,
          pinCode: '800001',
          headline: 'Test post',
          body: '',
          authorHandle: '@anonymous',
          createdAt: DateTime(2026, 8, 18),
        ),
      ]);
      final feed = await repo.listPosts(pinCode: '800001');
      expect(feed.first.authorHandle, '@anonymous');
      expect(feed.first.authorHandle, isNot(contains('+91')));
      expect(feed.first.authorHandle, isNot(contains('@gmail')));
    });
  });
}
