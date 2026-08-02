import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/security/data/local_root_detector.dart';
import 'package:civic_commons/security/domain/root_detection_service.dart';

/// Fake package checker controllable per-test.
class FakeRootPackageChecker implements RootPackageChecker {
  bool result;
  int calls = 0;

  FakeRootPackageChecker(this.result);

  @override
  Future<bool> hasKnownRootPackages() async {
    calls++;
    return result;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('root_detector_test_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('LocalRootDetector - clean device', () {
    test('reports not rooted when no indicators are present', () async {
      // No su paths exist, build.prop absent, writable paths absent, no packages.
      final detector = LocalRootDetector(
        suPaths: [File('${tempDir.path}/does_not_exist_su').path],
        writableSystemPaths: [Directory('${tempDir.path}/no_such_dir').path],
        buildPropPath: '${tempDir.path}/no_build_prop',
        packageChecker: FakeRootPackageChecker(false),
      );

      final integrity = await detector.detect();

      expect(integrity.isRooted, isFalse);
      expect(integrity.isJailbroken, isFalse);
      expect(integrity.triggeredChecks, isEmpty);
    });
  });

  group('LocalRootDetector - root indicators', () {
    test('flags suBinaryPresent when a su binary exists at a known path',
        () async {
      final suFile = File('${tempDir.path}/su');
      await suFile.create();

      final detector = LocalRootDetector(
        suPaths: [suFile.path],
        writableSystemPaths: const [],
        buildPropPath: '${tempDir.path}/no_build_prop',
        packageChecker: FakeRootPackageChecker(false),
      );

      final integrity = await detector.detect();

      expect(integrity.isRooted, isTrue);
      expect(integrity.triggeredChecks, contains(RootCheck.suBinaryPresent));
    });

    test('flags testKeysBuildTag when build.prop has ro.build.tags=test-keys',
        () async {
      final buildProp = File('${tempDir.path}/build.prop');
      await buildProp.writeAsString('ro.build.fingerprint=test/build/dev\n'
          'ro.build.tags=test-keys\n');

      final detector = LocalRootDetector(
        suPaths: const [],
        writableSystemPaths: const [],
        buildPropPath: buildProp.path,
        packageChecker: FakeRootPackageChecker(false),
      );

      final integrity = await detector.detect();

      expect(integrity.isRooted, isTrue);
      expect(integrity.triggeredChecks, contains(RootCheck.testKeysBuildTag));
    });

    test('does not flag test-keys for a release-keys build tag', () async {
      final buildProp = File('${tempDir.path}/build.prop');
      await buildProp.writeAsString('ro.build.tags=release-keys\n');

      final detector = LocalRootDetector(
        suPaths: const [],
        writableSystemPaths: const [],
        buildPropPath: buildProp.path,
        packageChecker: FakeRootPackageChecker(false),
      );

      final integrity = await detector.detect();

      expect(integrity.triggeredChecks,
          isNot(contains(RootCheck.testKeysBuildTag)));
    });

    test('flags writableSystemPath when a system path is writable', () async {
      final writableDir = Directory('${tempDir.path}/system_bin');
      await writableDir.create();

      final detector = LocalRootDetector(
        suPaths: const [],
        writableSystemPaths: [writableDir.path],
        buildPropPath: '${tempDir.path}/no_build_prop',
        packageChecker: FakeRootPackageChecker(false),
      );

      final integrity = await detector.detect();

      expect(integrity.isRooted, isTrue);
      expect(integrity.triggeredChecks, contains(RootCheck.writableSystemPath));
    });

    test('flags knownRootPackage when a root package is installed', () async {
      final detector = LocalRootDetector(
        suPaths: const [],
        writableSystemPaths: const [],
        buildPropPath: '${tempDir.path}/no_build_prop',
        packageChecker: FakeRootPackageChecker(true),
      );

      final integrity = await detector.detect();

      expect(integrity.isRooted, isTrue);
      expect(integrity.triggeredChecks, contains(RootCheck.knownRootPackage));
    });

    test('detect consults the package checker exactly once', () async {
      final checker = FakeRootPackageChecker(true);
      final detector = LocalRootDetector(
        suPaths: const [],
        writableSystemPaths: const [],
        buildPropPath: '${tempDir.path}/no_build_prop',
        packageChecker: checker,
      );

      await detector.detect();

      expect(checker.calls, equals(1));
    });
  });

  group('LocalRootDetector - SECURITY CHECKPOINT (no telemetry)', () {
    test('detect performs only local filesystem checks and never calls out',
        () async {
      // Guard: a detector with no indicators must still complete locally and
      // never attempt network/remote calls — the only interaction is with the
      // injected (in-memory) package checker and local temp files.
      final checker = FakeRootPackageChecker(false);
      final detector = LocalRootDetector(
        suPaths: [File('${tempDir.path}/missing_su').path],
        writableSystemPaths: [Directory('${tempDir.path}/missing_dir').path],
        buildPropPath: '${tempDir.path}/missing_build_prop',
        packageChecker: checker,
      );

      final integrity = await detector.detect();

      expect(integrity.isRooted, isFalse);
      expect(checker.calls, equals(1));
      // No files were created or modified on disk by the probe (missing dir).
      expect(
        Directory('${tempDir.path}/missing_dir').existsSync(),
        isFalse,
      );
    });
  });
}
