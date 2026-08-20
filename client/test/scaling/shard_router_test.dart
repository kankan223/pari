import 'package:civic_commons/scaling/domain/shard_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shard - Task 12.4', () {
    test('default shard has correct properties', () {
      const shard = Shard(
        id: 'shard_11',
        pinPrefix: '11',
        region: 'Delhi NCR',
      );
      expect(shard.id, 'shard_11');
      expect(shard.pinPrefix, '11');
      expect(shard.region, 'Delhi NCR');
      expect(shard.healthy, isTrue);
      expect(shard.loadFactor, 0);
    });

    test('copyWith creates new instance', () {
      const original = Shard(id: 's', pinPrefix: '11', region: 'R');
      final updated = original.copyWith(healthy: false, loadFactor: 0.8);
      expect(updated.healthy, isFalse);
      expect(updated.loadFactor, 0.8);
      expect(original.healthy, isTrue);
    });

    test('canAcceptRequests when healthy and load <0.9', () {
      const healthy = Shard(id: 's', pinPrefix: '11', region: 'R');
      const loaded =
          Shard(id: 's', pinPrefix: '11', region: 'R', loadFactor: 0.95);
      const unhealthy =
          Shard(id: 's', pinPrefix: '11', region: 'R', healthy: false);
      expect(healthy.canAcceptRequests, isTrue);
      expect(loaded.canAcceptRequests, isFalse);
      expect(unhealthy.canAcceptRequests, isFalse);
    });

    test('equality by id and pinPrefix', () {
      const a = Shard(id: 's1', pinPrefix: '11', region: 'R');
      const b = Shard(id: 's1', pinPrefix: '11', region: 'R');
      const c = Shard(id: 's2', pinPrefix: '11', region: 'R');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('ShardRouter - Task 12.4', () {
    late ShardRouter router;

    setUp(() {
      router = ShardRouter();
    });

    test('routeByPinCode returns correct shard', () {
      final shard = router.routeByPinCode('110001');
      expect(shard.pinPrefix, '11');
      expect(shard.region, 'Delhi NCR');
    });

    test('routeByPrefix returns correct shard', () {
      final shard = router.routeByPrefix('40');
      expect(shard.pinPrefix, '40');
      expect(shard.region, 'Mumbai');
    });

    test('routeByPinCode falls back to default for unknown prefix', () {
      final shard = router.routeByPinCode('000001');
      expect(shard.id, 'shard_default');
    });

    test('routeByPinCode throws for short pin', () {
      expect(
        () => router.routeByPinCode('1'),
        throwsArgumentError,
      );
    });

    test('healthyShards returns only healthy shards', () {
      final healthy = router.healthyShards;
      expect(healthy, isNotEmpty);
      for (final shard in healthy) {
        expect(shard.healthy, isTrue);
      }
    });

    test('leastLoadedShard returns shard with lowest load', () {
      final shard = router.leastLoadedShard;
      expect(shard, isNotNull);
      expect(shard!.loadFactor, 0);
    });

    test('shardsByLoad returns sorted list', () {
      final shards = router.shardsByLoad;
      expect(shards, isNotEmpty);
      for (var i = 1; i < shards.length; i++) {
        expect(
          shards[i].loadFactor,
          greaterThanOrEqualTo(shards[i - 1].loadFactor),
        );
      }
    });

    test('shardCount returns total shards', () {
      expect(router.shardCount, defaultShards.length);
    });

    test('avgLoadFactor computes correctly', () {
      expect(router.avgLoadFactor, 0);
    });

    test('defaultShards covers all Indian regions', () {
      expect(defaultShards, contains('11')); // Delhi
      expect(defaultShards, contains('40')); // Mumbai
      expect(defaultShards, contains('60')); // Chennai
      expect(defaultShards, contains('70')); // Kolkata
      expect(defaultShards, contains('default'));
    });
  });
}
