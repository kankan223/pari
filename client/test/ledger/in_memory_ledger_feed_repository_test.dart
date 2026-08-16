import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/ledger/domain/ledger_vote.dart';
import 'package:civic_commons/ledger/domain/peer_review.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerPost _post({
  required String id,
  LedgerCategory category = LedgerCategory.civicInfrastructure,
  String pinCode = '800001',
  String? headline,
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

void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);
  final t1 = DateTime.utc(2026, 8, 10, 13);
  final t2 = DateTime.utc(2026, 8, 10, 14);

  group('InMemoryLedgerFeedRepository', () {
    test('listPosts scopes strictly by pin code (FR-L1)', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'a', pinCode: '800001', createdAt: t0),
          _post(id: 'b', pinCode: '800002', createdAt: t1),
        ],
      );
      final posts = await repo.listPosts(pinCode: '800001');
      expect(posts.map((p) => p.id), ['a']);
    });

    test('listPosts filters by category', () async {
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
      final posts = await repo.listPosts(
          pinCode: '800001', category: LedgerCategory.satireAndCulture);
      expect(posts.map((p) => p.id), ['b']);
    });

    test('published posts sort above peer-review/shadow posts, newest first',
        () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'old-published', createdAt: t0),
          _post(
              id: 'review', status: LedgerPostStatus.peerReview, createdAt: t2),
          _post(id: 'new-published', createdAt: t2),
          _post(
              id: 'shadow',
              status: LedgerPostStatus.shadowQueue,
              createdAt: t1),
        ],
      );
      final posts = await repo.listPosts(pinCode: '800001');
      // Published posts first (newest→oldest), then pending posts
      // (newest→oldest within the pending group).
      expect(
        posts.map((p) => p.id),
        ['new-published', 'old-published', 'review', 'shadow'],
      );
    });

    test('getById returns null for missing ids', () async {
      final repo =
          InMemoryLedgerFeedRepository(seed: [_post(id: 'a', createdAt: t0)]);
      expect(await repo.getById('a'), isNotNull);
      expect(await repo.getById('missing'), isNull);
    });

    test('vote toggles directions deterministically (Task 7.5)', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', voteCount: 10, createdAt: t0)],
      );
      // Fresh upvote: +1.
      await repo.vote('a', LedgerVoteDirection.up);
      expect((await repo.getById('a'))!.voteCount, 11);
      expect((await repo.getById('a'))!.myVote, LedgerVoteDirection.up);
      // Same direction again toggles OFF: back to 10, none.
      await repo.vote('a', LedgerVoteDirection.up);
      expect((await repo.getById('a'))!.voteCount, 10);
      expect((await repo.getById('a'))!.myVote, LedgerVoteDirection.none);
      // Fresh downvote: -1.
      await repo.vote('a', LedgerVoteDirection.down);
      expect((await repo.getById('a'))!.voteCount, 9);
      expect((await repo.getById('a'))!.myVote, LedgerVoteDirection.down);
      // Switching down -> up moves by 2.
      await repo.vote('a', LedgerVoteDirection.up);
      expect((await repo.getById('a'))!.voteCount, 11);
      expect((await repo.getById('a'))!.myVote, LedgerVoteDirection.up);
      // Unknown ids are no-ops.
      await repo.vote('missing', LedgerVoteDirection.up);
    });

    test('downvotes are reversible even from zero (Task 7.5)', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', voteCount: 0, createdAt: t0)],
      );
      // A downvote takes the net tally negative (downvotes exceed upvotes).
      await repo.vote('a', LedgerVoteDirection.down);
      expect((await repo.getById('a'))!.voteCount, -1);
      expect((await repo.getById('a'))!.myVote, LedgerVoteDirection.down);
      // Undoing it restores the original count EXACTLY — toggles are
      // invertible (no clamp drift).
      await repo.vote('a', LedgerVoteDirection.down);
      expect((await repo.getById('a'))!.voteCount, 0);
      expect((await repo.getById('a'))!.myVote, LedgerVoteDirection.none);
    });

    test('applyReview increments approvals and publishes at 3/3 (Task 7.6)',
        () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(
              id: 'a',
              status: LedgerPostStatus.peerReview,
              verifiedReviewers: 2,
              createdAt: t0),
        ],
      );
      final status = await repo.applyReview('a', PeerReviewDecision.approved);
      expect(status, LedgerPostStatus.published);
      expect((await repo.getById('a'))!.verifiedReviewers, 3);
      expect((await repo.getById('a'))!.status, LedgerPostStatus.published);
    });

    test('applyReview reject/flag never advance the consensus (Task 7.6)',
        () async {
      for (final decision in [
        PeerReviewDecision.rejected,
        PeerReviewDecision.flagged,
      ]) {
        final repo = InMemoryLedgerFeedRepository(
          seed: [
            _post(
                id: 'a',
                status: LedgerPostStatus.peerReview,
                verifiedReviewers: 2,
                createdAt: t0),
          ],
        );
        final status = await repo.applyReview('a', decision);
        expect(status, LedgerPostStatus.peerReview,
            reason: '${decision.wireName} must not advance the gate');
        expect((await repo.getById('a'))!.verifiedReviewers, 2);
        expect((await repo.getById('a'))!.status, LedgerPostStatus.peerReview);
      }
    });

    test('applyReview on a published post is a no-op (immutable)', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(
              id: 'a',
              status: LedgerPostStatus.published,
              verifiedReviewers: 3,
              createdAt: t0),
        ],
      );
      final status = await repo.applyReview('a', PeerReviewDecision.approved);
      expect(status, LedgerPostStatus.published);
      expect((await repo.getById('a'))!.verifiedReviewers, 3);
    });

    test('applyReview on a missing id is a safe no-op', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', createdAt: t0)],
      );
      final status =
          await repo.applyReview('missing', PeerReviewDecision.approved);
      expect(status, LedgerPostStatus.peerReview);
    });

    test('currentEdition returns the seeded edition', () async {
      final repo = InMemoryLedgerFeedRepository(edition: 412);
      expect(await repo.currentEdition(), 412);
    });

    test('seed() populates the local cache', () async {
      final repo = InMemoryLedgerFeedRepository();
      repo.seed([_post(id: 'a', createdAt: t0)]);
      expect(await repo.getById('a'), isNotNull);
    });
  });
}
