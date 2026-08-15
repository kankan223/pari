/// Specific root/jailbreak indicators that were found on the device.
///
/// These are individual *local* checks. The set of triggered checks is used
/// only to inform a local warning decision — it is never transmitted anywhere.
enum RootCheck {
  /// A `su` binary was found at a well-known system path.
  suBinaryPresent,

  /// The Android build tag is `test-keys` (typical of custom/rooted ROMs).
  testKeysBuildTag,

  /// A known root-management application is installed (e.g. Magisk, SuperSU).
  knownRootPackage,

  /// A system directory that is only writable on rooted devices was writable.
  writableSystemPath,
}

/// Result of a local, on-device root/jailbreak check.
///
/// This is a pure data model produced by the data layer and consumed by the
/// domain policy. It contains only booleans and enum values — no personal
/// data, no device identifiers, and nothing that could fingerprint a device.
class DeviceIntegrity {
  /// True when at least one root indicator was found.
  final bool isRooted;

  /// True when the device appears to be jailbroken (iOS only; false on Android).
  final bool isJailbroken;

  /// The individual checks that triggered, for a precise local warning.
  final List<RootCheck> triggeredChecks;

  const DeviceIntegrity({
    required this.isRooted,
    required this.isJailbroken,
    required this.triggeredChecks,
  });

  /// A device with no detected indicators.
  static const DeviceIntegrity clean = DeviceIntegrity(
    isRooted: false,
    isJailbroken: false,
    triggeredChecks: [],
  );
}

/// Port (domain use case) for local root/jailbreak detection.
///
/// Responsibilities:
/// 1. Detect root/jailbreak indicators using only on-device sources
///    (filesystem checks, installed-package queries).
/// 2. Return a [DeviceIntegrity] result for the local security policy.
///
/// Security contract (SECURITY CHECKPOINT):
/// - Detection is strictly LOCAL. The implementation performs no network
///   calls and transmits no data — not even an aggregated "isRooted" boolean
///   — to any server.
/// - No device fingerprinting data (model, serial, IMEI, Android ID, MAC,
///   locale, etc.) is ever collected or used.
abstract class RootDetectionService {
  /// Runs all local checks and returns the aggregated integrity result.
  Future<DeviceIntegrity> detect();
}
