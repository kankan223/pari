import 'package:civic_commons/geo/domain/explore_radius.dart';
import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/feed_scope.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerPost _post({
  required String id,
  String pinCode = '800001',
  String? district = 'Patna',
  LedgerCategory category = LedgerCategory.civicInfrastructure,
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
      createdAt: createdAt,
    );

void main() {
  final now = DateTime.utc(2026, 8, 15, 12);

  group('Dynamic radius expansion (Task 7.3)', () {
    test('sparse local feed (<5 recent) expands to same-district posts',
        () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'local1', createdAt: now.subtract(const Duration(days: 1))),
          _post(
              id: 'nearby1',
              pinCode: '800002',
              district: 'Patna',
              createdAt: now.subtract(const Duration(hours: 2))),
          _post(
              id: 'other-district',
              pinCode: '560001',
              district: 'Bengaluru Urban',
              createdAt: now.subtract(const Duration(hours: 1))),
        ],
      );
      final result = await repo.listScoped(
        FeedScope(
          pinCode: '800001',
          radius: ExploreRadius.district10km,
          now: () => now,
        ),
      );

      expect(result.expanded, isTrue);
      expect(result.nearbyCount, 1);
      expect(result.nearbyIds, {'nearby1'});
      // Blended: local + same-district only (other district excluded).
      expect(result.posts.map((p) => p.id), containsAll(['local1', 'nearby1']));
      expect(result.posts.any((p) => p.id == 'other-district'), isFalse);
    });

    test('dense local feed (≥5 recent) does NOT expand', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          for (var i = 0; i < 5; i++)
            _post(id: 'local$i', createdAt: now.subtract(Duration(days: i))),
          _post(
              id: 'nearby1',
              pinCode: '800002',
              district: 'Patna',
              createdAt: now.subtract(const Duration(hours: 2))),
        ],
      );
      final result = await repo.listScoped(
        FeedScope(
          pinCode: '800001',
          radius: ExploreRadius.district10km,
          now: () => now,
        ),
      );

      expect(result.expanded, isFalse);
      expect(result.nearbyCount, 0);
      expect(result.posts.map((p) => p.id), hasLength(5));
    });

    test('7-day window: old posts do not count toward the threshold', () async {
      // 4 posts but 3 are older than 7 days → still sparse → expands.
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'fresh', createdAt: now.subtract(const Duration(days: 1))),
          for (var i = 0; i < 3; i++)
            _post(id: 'old$i', createdAt: now.subtract(Duration(days: 10 + i))),
          _post(
              id: 'nearby1',
              pinCode: '800002',
              district: 'Patna',
              createdAt: now.subtract(const Duration(hours: 2))),
        ],
      );
      final result = await repo.listScoped(
        FeedScope(
          pinCode: '800001',
          radius: ExploreRadius.district10km,
          now: () => now,
        ),
      );

      expect(result.expanded, isTrue);
      expect(result.nearbyIds, {'nearby1'});
    });

    test('radius none = local-only feed, never expands', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'local1', createdAt: now),
          _post(
              id: 'nearby1',
              pinCode: '800002',
              district: 'Patna',
              createdAt: now),
        ],
      );
      final result = await repo.listScoped(
        FeedScope(
            pinCode: '800001', radius: ExploreRadius.none, now: () => now),
      );

      expect(result.expanded, isFalse);
      expect(result.posts.map((p) => p.id), ['local1']);
    });

    test('no district signal for the pin → no expansion (safe default)',
        () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'local1', district: null, createdAt: now),
          _post(
              id: 'nearby1',
              pinCode: '800002',
              district: 'Patna',
              createdAt: now),
        ],
      );
      final result = await repo.listScoped(
        FeedScope(
          pinCode: '800001',
          radius: ExploreRadius.district10km,
          now: () => now,
        ),
      );

      expect(result.expanded, isFalse);
      expect(result.nearbyCount, 0);
    });

    test('category filter applies to BOTH local and nearby posts', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'local-civic', createdAt: now),
          _post(
              id: 'nearby-satire',
              pinCode: '800002',
              district: 'Patna',
              category: LedgerCategory.satireAndCulture,
              createdAt: now),
          _post(
              id: 'nearby-civic',
              pinCode: '800002',
              district: 'Patna',
              createdAt: now.subtract(const Duration(hours: 1))),
        ],
      );
      final result = await repo.listScoped(
        FeedScope(
          pinCode: '800001',
          radius: ExploreRadius.district10km,
          category: LedgerCategory.civicInfrastructure,
          now: () => now,
        ),
      );

      expect(result.posts.map((p) => p.id),
          containsAll(['local-civic', 'nearby-civic']));
      expect(result.posts.any((p) => p.id == 'nearby-satire'), isFalse);
      expect(result.nearbyIds, {'nearby-civic'});
    });

    test('blended feed is a SINGLE chronological list (no sections)', () async {
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          _post(
              id: 'local-old',
              createdAt: now.subtract(const Duration(days: 3))),
          _post(
              id: 'nearby-new',
              pinCode: '800002',
              district: 'Patna',
              createdAt: now.subtract(const Duration(hours: 1))),
        ],
      );
      final result = await repo.listScoped(
        FeedScope(
          pinCode: '800001',
          radius: ExploreRadius.nearby5km,
          now: () => now,
        ),
      );

      // One list, chronological (newest first) — nearby and local interleave.
      final ids = result.posts.map((p) => p.id).toList();
      expect(ids, ['nearby-new', 'local-old']);
    });
  });
}
