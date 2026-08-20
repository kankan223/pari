/// Types of penetration test scenarios (Task 13.4).
///
/// Each scenario represents a specific attack vector that should be tested
/// against the Civic Commons codebase. The scenarios are pure domain models
/// with zero PII.
enum PenetrationTestType {
  /// SQL injection attempts via malformed input.
  sqlInjection,

  /// Buffer overflow / oversized input attempts.
  bufferOverflow,

  /// Timing attack simulation on cryptographic operations.
  timingAttack,

  /// Authentication bypass attempts.
  authBypass,

  /// Session fixation / hijacking attempts.
  sessionHijacking,

  /// Privilege escalation attempts.
  privilegeEscalation,

  /// Data leakage through error messages or logs.
  dataLeakage,

  /// Denial of service via resource exhaustion.
  denialOfService,

  /// Cryptographic downgrade attacks.
  cryptoDowngrade,

  /// Input fuzzing with malformed data.
  inputFuzzing;

  /// Human-readable label for display.
  String get label {
    switch (this) {
      case PenetrationTestType.sqlInjection:
        return 'SQL Injection';
      case PenetrationTestType.bufferOverflow:
        return 'Buffer Overflow';
      case PenetrationTestType.timingAttack:
        return 'Timing Attack';
      case PenetrationTestType.authBypass:
        return 'Auth Bypass';
      case PenetrationTestType.sessionHijacking:
        return 'Session Hijacking';
      case PenetrationTestType.privilegeEscalation:
        return 'Privilege Escalation';
      case PenetrationTestType.dataLeakage:
        return 'Data Leakage';
      case PenetrationTestType.denialOfService:
        return 'Denial of Service';
      case PenetrationTestType.cryptoDowngrade:
        return 'Crypto Downgrade';
      case PenetrationTestType.inputFuzzing:
        return 'Input Fuzzing';
    }
  }
}

/// Result of a single penetration test scenario (Task 13.4).
class PenetrationTestResult {
  /// Type of test that was executed.
  final PenetrationTestType type;

  /// Whether the application抵御了 the attack.
  final bool resisted;

  /// Description of the test execution.
  final String description;

  /// Duration of the test in milliseconds.
  final int durationMs;

  const PenetrationTestResult({
    required this.type,
    required this.resisted,
    required this.description,
    required this.durationMs,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PenetrationTestResult &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          resisted == other.resisted;

  @override
  int get hashCode => type.hashCode ^ resisted.hashCode;
}
