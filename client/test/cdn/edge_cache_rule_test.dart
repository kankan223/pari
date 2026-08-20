import 'package:civic_commons/cdn/domain/edge_cache_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EdgeCacheRule - Task 12.3', () {
    test('default rule has correct properties', () {
      const rule = EdgeCacheRule(
        assetType: 'module_video',
        cacheControl: 'public, max-age=86400',
        ttlSeconds: 86400,
      );
      expect(rule.assetType, 'module_video');
      expect(rule.cacheControl, 'public, max-age=86400');
      expect(rule.ttlSeconds, 86400);
      expect(rule.immutable, isFalse);
      expect(rule.staleWhileRevalidate, isFalse);
      expect(rule.vary, isNull);
    });

    test('immutableModule factory creates correct rule', () {
      const rule = EdgeCacheRule.immutableModule(assetType: 'module_video');
      expect(rule.assetType, 'module_video');
      expect(rule.immutable, isTrue);
      expect(rule.cacheControl, contains('immutable'));
      expect(rule.ttlSeconds, 31536000); // 1 year
    });

    test('mutableMetadata factory creates correct rule', () {
      const rule = EdgeCacheRule.mutableMetadata(assetType: 'module_metadata');
      expect(rule.assetType, 'module_metadata');
      expect(rule.immutable, isFalse);
      expect(rule.staleWhileRevalidate, isTrue);
      expect(rule.cacheControl, contains('stale-while-revalidate'));
    });

    test('apiResponse factory creates correct rule', () {
      const rule = EdgeCacheRule.apiResponse(assetType: 'presigned_url');
      expect(rule.assetType, 'presigned_url');
      expect(rule.cacheControl, contains('private'));
      expect(rule.immutable, isFalse);
      expect(rule.staleWhileRevalidate, isFalse);
    });

    test('equality by assetType and ttlSeconds', () {
      const a = EdgeCacheRule(
        assetType: 'video',
        cacheControl: 'public',
        ttlSeconds: 3600,
      );
      const b = EdgeCacheRule(
        assetType: 'video',
        cacheControl: 'public',
        ttlSeconds: 3600,
      );
      const c = EdgeCacheRule(
        assetType: 'video',
        cacheControl: 'public',
        ttlSeconds: 7200,
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('defaultEdgeCacheRules covers all asset types', () {
      expect(defaultEdgeCacheRules, hasLength(7));
      final types = defaultEdgeCacheRules.map((r) => r.assetType).toSet();
      expect(types, contains('module_video'));
      expect(types, contains('module_pdf'));
      expect(types, contains('module_audio'));
      expect(types, contains('module_metadata'));
      expect(types, contains('syllabus_tree'));
      expect(types, contains('presigned_url'));
      expect(types, contains('module_manifest'));
    });
  });
}
