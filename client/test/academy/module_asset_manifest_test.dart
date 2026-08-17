import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:civic_commons/academy/domain/module_asset_manifest.dart';
import 'package:civic_commons/academy/domain/offline_module_cache.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

AcademyModule _module() => AcademyModule.parse(
      moduleId: _m1,
      domainId: 'civics',
      title: 'Fundamentals of Civic Rights',
      durationMinutes: 18,
      locale: 'en',
      contentRef: 'civics/rights-fundamentals/mod-01',
    );

void main() {
  group('ModuleAssetManifest (Task 9.4 — manifest generation)', () {
    test('generates the video asset from the module content ref + size table',
        () {
      final manifest = ModuleAssetManifest.generateFor(
        _module(),
        sizes: {'civics/rights-fundamentals/mod-01': 24 * 1024 * 1024},
      );

      expect(manifest.moduleId, _m1);
      expect(manifest.moduleTitle, 'Fundamentals of Civic Rights');
      final video = manifest.assets.single;
      expect(video.kind, ModuleAssetKind.video);
      // The asset carries the module's OPAQUE content ref — never a URL.
      expect(video.ref, 'civics/rights-fundamentals/mod-01');
      expect(video.sizeBytes, 24 * 1024 * 1024);
      expect(manifest.totalSizeBytes, 24 * 1024 * 1024);
    });

    test('includes the derived transcript asset when the table provides one',
        () {
      final manifest = ModuleAssetManifest.generateFor(
        _module(),
        sizes: {
          'civics/rights-fundamentals/mod-01': 24 * 1024 * 1024,
          'civics/rights-fundamentals/mod-01/transcript': 140 * 1024,
        },
      );

      expect(manifest.assets, hasLength(2));
      final transcript = manifest.assets[1];
      expect(transcript.kind, ModuleAssetKind.transcript);
      expect(transcript.ref, 'civics/rights-fundamentals/mod-01/transcript');
      expect(transcript.sizeBytes, 140 * 1024);
      expect(manifest.totalSizeBytes, 24 * 1024 * 1024 + 140 * 1024);
    });

    test('omits the transcript asset when the table has none', () {
      final manifest = ModuleAssetManifest.generateFor(
        _module(),
        sizes: const {},
      );

      expect(manifest.assets, hasLength(1));
      expect(manifest.isEmpty, isFalse);
      // Unknown refs fall back to the deterministic defaults.
      expect(manifest.totalSizeBytes, 64 * 1024 * 1024);
    });

    test('is deterministic — identical inputs produce identical manifests', () {
      const sizes = {
        'civics/rights-fundamentals/mod-01': 24 * 1024 * 1024,
        'civics/rights-fundamentals/mod-01/transcript': 140 * 1024,
      };
      final a = ModuleAssetManifest.generateFor(_module(), sizes: sizes);
      final b = ModuleAssetManifest.generateFor(_module(), sizes: sizes);

      expect(a.totalSizeBytes, b.totalSizeBytes);
      expect(a.assets, b.assets); // value equality on assets
      expect(a.moduleId, b.moduleId);
    });

    test('SECURITY: manifest carries zero identity', () {
      final manifest = ModuleAssetManifest.generateFor(
        _module(),
        sizes: {'civics/rights-fundamentals/mod-01': 1024},
      );

      // The only identifiers are the UUID module id + opaque content refs.
      final identifiers = manifest.assets.map((a) => a.ref).toList();
      expect(identifiers, isNot(contains(RegExp(r'[0-9a-f]{64}'))));
      expect(identifiers.join(' ').toLowerCase(),
          isNot(contains(RegExp(r'@|\+?\d{10,}'))));
      // No URL shapes can be produced from a manifest.
      for (final a in manifest.assets) {
        expect(a.ref.startsWith('http'), isFalse);
      }
    });
  });

  group('OfflineCacheStatus (strict wire names)', () {
    test('wire names round-trip', () {
      for (final status in OfflineCacheStatus.values) {
        expect(
          OfflineCacheStatus.fromWireName(status.wireName),
          status,
        );
      }
    });

    test('unknown wire name throws (corrupt row cannot masquerade)', () {
      expect(
        () => OfflineCacheStatus.fromWireName('synced'),
        throwsArgumentError,
      );
    });
  });

  group('ModuleAssetKind (strict wire names)', () {
    test('wire names round-trip', () {
      for (final kind in ModuleAssetKind.values) {
        expect(ModuleAssetKind.fromWireName(kind.wireName), kind);
      }
    });

    test('unknown kind throws', () {
      expect(() => ModuleAssetKind.fromWireName('audio'), throwsArgumentError);
    });
  });
}
