import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/ledger/domain/peer_review.dart';
import 'package:civic_commons/ledger/domain/peer_review_sink.dart';
import 'package:civic_commons/state/data/local_ledger_review_bloc.dart';
import 'package:civic_commons/state/domain/ledger_review_state.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerPost _post({
  required String id,
  String pinCode = '800001',
  int verifiedReviewers = 0,
  LedgerPostStatus status = LedgerPostStatus.peerReview,
  required DateTime createdAt,
}) =>
    LedgerPost(
      id: id,
      category: LedgerCategory.civicInfrastructure,
      pinCode: pinCode,
      headline: 'Headline $id',
      body: 'Body $id',
      authorHandle: 'handle_$id',
      verifiedReviewers: verifiedReviewers,
      status: status,
      createdAt: createdAt,
    );

void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);
  final t1 = DateTime.utc(2026, 8, 10, 13);

  group('LedgerReviewBloc (Task 7.6)', () {
    test('start() projects the pending queue (review + shadow, newest first)',
        () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'old', createdAt: t0),
          _post(id: 'new', status: LedgerPostStatus.shadowQueue, createdAt: t1),
          _post(
              id: 'published',
              status: LedgerPostStatus.published,
              createdAt: t0),
        ],
      );
      final bloc = LocalLedgerReviewBloc(repository: repo);
      final states = <LedgerReviewState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();

      final state = states.last;
      expect(state.status, LedgerReviewStatus.loaded);
      // Review + shadow entries only; published posts are excluded.
      expect(state.queue.map((e) => e.postId), ['new', 'old']);
      expect(state.shadowQueueCount, 1);
      expect(state.queue.first.reviewerHandles, isNotEmpty);
      // Blinded handles only — never raw hashes.
      for (final e in state.queue) {
        for (final h in e.reviewerHandles) {
          expect(h.startsWith('reviewer_'), isTrue);
          expect(RegExp(r'[0-9a-f]{64}').hasMatch(h), isFalse);
        }
      }

      await sub.cancel();
      await bloc.close();
    });

    test('submit(approve) records the decision and re-projects', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', verifiedReviewers: 2, createdAt: t0)],
      );
      final sink = _RecordingSink();
      final bloc = LocalLedgerReviewBloc(repository: repo, reviews: sink);
      final states = <LedgerReviewState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();

      await bloc.submit('a', PeerReviewDecision.approved);
      await pumpEventQueue();

      // 3rd approval -> consensus -> post publishes and leaves the queue.
      expect((await repo.getById('a'))!.verifiedReviewers, 3);
      expect((await repo.getById('a'))!.status, LedgerPostStatus.published);
      expect(sink.saved.single.postId, 'a');
      expect(sink.saved.single.decision, PeerReviewDecision.approved);
      expect(states.last.queue, isEmpty);

      await sub.cancel();
      await bloc.close();
    });

    test('submit(reject/flag) records but never advances the consensus',
        () async {
      for (final decision in [
        PeerReviewDecision.rejected,
        PeerReviewDecision.flagged,
      ]) {
        final repo = InMemoryLedgerFeedRepository(
          seed: [_post(id: 'a', verifiedReviewers: 2, createdAt: t0)],
        );
        final sink = _RecordingSink();
        final bloc = LocalLedgerReviewBloc(repository: repo, reviews: sink);
        await bloc.start('800001');
        await pumpEventQueue();

        await bloc.submit('a', decision);
        await pumpEventQueue();

        expect((await repo.getById('a'))!.verifiedReviewers, 2,
            reason: '${decision.wireName} must not count toward consensus');
        expect((await repo.getById('a'))!.status, LedgerPostStatus.peerReview);
        await bloc.close();
      }
    });

    test('submitting marks the post as reviewed by me (REVIEWED state)',
        () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', createdAt: t0)],
      );
      final bloc = LocalLedgerReviewBloc(repository: repo);
      final states = <LedgerReviewState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();

      await bloc.submit('a', PeerReviewDecision.rejected);
      await pumpEventQueue();

      expect(states.last.queue.single.reviewedByMe, isTrue);
      expect(states.last.queue.single.consensusReached, isFalse);

      await sub.cancel();
      await bloc.close();
    });

    test('a failing sink degrades gracefully — decision still applies',
        () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [_post(id: 'a', verifiedReviewers: 2, createdAt: t0)],
      );
      final bloc =
          LocalLedgerReviewBloc(repository: repo, reviews: _ThrowingSink());
      final states = <LedgerReviewState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();

      // The 3rd approval still publishes locally even though the sink threw.
      await bloc.submit('a', PeerReviewDecision.approved);
      await pumpEventQueue();

      expect((await repo.getById('a'))!.status, LedgerPostStatus.published);
      expect(states.last.queue, isEmpty);

      await sub.cancel();
      await bloc.close();
    });

    test('entry projections carry ONLY non-PII fields', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'a', createdAt: t0),
        ],
      );
      final bloc = LocalLedgerReviewBloc(repository: repo);
      final states = <LedgerReviewState>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();

      final entry = states.last.queue.single;
      expect(entry.postId, 'a');
      expect(entry.headline, 'Headline a');
      expect(entry.authorHandle, 'handle_a'); // non-PII display handle
      expect(entry.reviewerHandles.every((h) => h.startsWith('reviewer_')),
          isTrue);

      await sub.cancel();
      await bloc.close();
    });
  });
}

class _RecordingSink implements PeerReviewSink {
  final List<PeerReviewSubmission> saved = [];

  @override
  Future<List<PeerReviewRecord>> localDecisions() async => const [];

  @override
  Future<String> save(PeerReviewSubmission submission) async {
    saved.add(submission);
    return 'id';
  }
}

class _ThrowingSink implements PeerReviewSink {
  @override
  Future<List<PeerReviewRecord>> localDecisions() async => const [];

  @override
  Future<String> save(PeerReviewSubmission submission) async {
    throw StateError('queue down');
  }
}
