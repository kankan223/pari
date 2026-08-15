import 'dart:io';

import '../domain/root_detection_service.dart';

/// Local-only source of known root-management package names.
///
/// Abstracted so the data layer can query the installed-package list through
/// a platform channel while tests inject an in-memory fake. No package list
/// is ever transmitted anywhere.
abstract class RootPackageChecker {
  /// Returns true if any known root-management package is installed.
  Future<bool> hasKnownRootPackages();
}

/// Local, on-device root/jailbreak detection (data layer).
///
/// Performs filesystem checks only — no network, no telemetry, no device
/// fingerprinting. Everything is configurable so tests can point at temp
/// paths and a fake package checker:
///
/// - `su` binaries at well-known paths (`/system/bin/su`, etc.)
/// - Android `test-keys` build tag (from `ro.build.tags` in build.prop)
/// - Writable system paths that are read-only on stock devices
/// - Known root-management apps via [RootPackageChecker]
///
/// SECURITY CHECKPOINT (Task 2.6): This detector never sends data to a
/// server. It reads local files and (via the injected checker) the local
/// package list, then reduces everything to a [DeviceIntegrity] boolean
/// summary. No device identifiers are read or emitted.
class LocalRootDetector implements RootDetectionService {
  /// Well-known locations of the `su` binary on rooted Android devices.
  static const List<String> defaultSuPaths = [
    '/system/bin/su',
    '/system/xbin/su',
    '/sbin/su',
    '/su/bin/su',
    '/system/bin/.ext/.su',
    '/system/sd/xbin/su',
    '/data/local/bin/su',
    '/data/local/xbin/su',
    '/data/adb/magisk/busybox',
  ];

  /// Well-known directories that are only writable on rooted devices.
  static const List<String> defaultWritableSystemPaths = [
    '/system/bin',
    '/system/xbin',
    '/sbin',
  ];

  /// Default build.prop location on Android.
  static const String defaultBuildPropPath = '/system/build.prop';

  final List<String> _suPaths;
  final List<String> _writablePaths;
  final String _buildPropPath;
  final RootPackageChecker _packageChecker;

  LocalRootDetector({
    List<String> suPaths = defaultSuPaths,
    List<String> writableSystemPaths = defaultWritableSystemPaths,
    String buildPropPath = defaultBuildPropPath,
    RootPackageChecker? packageChecker,
  })  : _suPaths = suPaths,
        _writablePaths = writableSystemPaths,
        _buildPropPath = buildPropPath,
        _packageChecker = packageChecker ?? _NoopRootPackageChecker();

  @override
  Future<DeviceIntegrity> detect() async {
    final checks = <RootCheck>[];

    // 1. su binary present?
    for (final path in _suPaths) {
      if (File(path).existsSync()) {
        checks.add(RootCheck.suBinaryPresent);
        break;
      }
    }

    // 2. test-keys build tag?
    if (_hasTestKeysBuildTag()) {
      checks.add(RootCheck.testKeysBuildTag);
    }

    // 3. writable system paths?
    for (final path in _writablePaths) {
      if (_isWritable(path)) {
        checks.add(RootCheck.writableSystemPath);
        break;
      }
    }

    // 4. known root packages installed?
    if (await _packageChecker.hasKnownRootPackages()) {
      checks.add(RootCheck.knownRootPackage);
    }

    final isRooted = checks.isNotEmpty;
    return DeviceIntegrity(
      isRooted: isRooted,
      isJailbroken: false, // jailbreak detection is iOS-only; not on Android
      triggeredChecks: List.unmodifiable(checks),
    );
  }

  /// Reads `ro.build.tags` from build.prop and checks for `test-keys`.
  bool _hasTestKeysBuildTag() {
    try {
      final file = File(_buildPropPath);
      if (!file.existsSync()) {
        return false;
      }
      final lines = file.readAsLinesSync();
      for (final line in lines) {
        if (line.trimLeft().startsWith('ro.build.tags=')) {
          return line.trimLeft().substring('ro.build.tags='.length) ==
              'test-keys';
        }
      }
      return false;
    } catch (_) {
      return false; // unreadable build.prop ⇒ treat as non-root (fail open)
    }
  }

  /// Probes whether [path] is writable by creating and deleting a scratch
  /// file. On stock devices these system locations are read-only (probe
  /// throws ⇒ false); on rooted devices the probe typically succeeds.
  bool _isWritable(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        return false;
      }
      final probe = File('${dir.path}/.civic_probe_${_randomSuffix()}');
      try {
        probe.createSync();
        return probe.existsSync();
      } finally {
        // Always attempt cleanup so no probe residue is left behind.
        try {
          probe.deleteSync();
        } catch (_) {}
      }
    } catch (_) {
      return false;
    }
  }

  String _randomSuffix() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(16);
}

/// Default checker when none is injected: reports no root packages so
/// detection is purely filesystem-based unless a real checker is provided.
class _NoopRootPackageChecker implements RootPackageChecker {
  @override
  Future<bool> hasKnownRootPackages() async => false;
}
