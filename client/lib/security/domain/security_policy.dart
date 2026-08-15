import 'root_detection_service.dart';

/// Severity of a device-security decision.
///
/// Only two levels exist on purpose: `normal` and `warning`. The application
/// never blocks access based on root/jailbreak status — it degrades
/// gracefully with a warning, per the master plan.
enum SecuritySeverity {
  /// No integrity concerns detected; proceed normally.
  normal,

  /// A root/jailbreak indicator was found; show a warning but allow use.
  warning,
}

/// Result of evaluating a [DeviceIntegrity] against the security policy.
///
/// Carries only local, non-fingerprinting information (severity + which
/// generic checks triggered). No device identifiers are included.
class SecurityDecision {
  final SecuritySeverity severity;

  /// The generic checks that triggered the warning (for a precise message).
  final List<RootCheck> triggeredChecks;

  /// Whether the user may continue using the screen.
  ///
  /// This is ALWAYS true: the design mandate is *warning, not block*.
  final bool allowsContinue;

  const SecurityDecision({
    required this.severity,
    required this.triggeredChecks,
    this.allowsContinue = true,
  });

  /// A decision to proceed without any warning.
  static const SecurityDecision normal = SecurityDecision(
    severity: SecuritySeverity.normal,
    triggeredChecks: [],
  );

  /// Builds a warning decision from the checks that triggered.
  factory SecurityDecision.warning(List<RootCheck> checks) => SecurityDecision(
        severity: SecuritySeverity.warning,
        triggeredChecks: List.unmodifiable(checks),
      );
}

/// Domain use case that turns a local [DeviceIntegrity] result into a
/// [SecurityDecision].
///
/// Graceful degradation policy (from MASTER_PLAN Task 2.6):
/// - Clean device        → normal decision, no UI change.
/// - Rooted/jailbroken   → warning decision; the user is informed but is
///                          NEVER blocked from using the app.
///
/// Security contract:
/// - This use case is pure logic — no I/O, no channels, no telemetry.
/// - It never collects, stores, or emits any device fingerprinting data.
class DeviceSecurityPolicy {
  const DeviceSecurityPolicy();

  /// Evaluates a local integrity result into a decision.
  SecurityDecision evaluate(DeviceIntegrity integrity) {
    if (!integrity.isRooted && !integrity.isJailbroken) {
      return SecurityDecision.normal;
    }
    return SecurityDecision.warning(integrity.triggeredChecks);
  }
}
