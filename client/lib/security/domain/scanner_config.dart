import 'vulnerability_severity.dart';
import 'vulnerability_type.dart';

/// A vulnerability scanning pattern (Task 13.4).
///
/// Defines a regex-based pattern for detecting specific vulnerability types
/// in source code. Each pattern carries metadata for the scanner to produce
/// structured findings.
class ScannerPattern {
  /// Regex pattern to match in source code.
  final String pattern;

  /// Category of vulnerability this pattern detects.
  final VulnerabilityType vulnerabilityType;

  /// Severity when this pattern matches.
  final VulnerabilitySeverity severity;

  /// Human-readable description of the vulnerability.
  final String description;

  /// OWASP recommendation for remediation.
  final String recommendation;

  const ScannerPattern({
    required this.pattern,
    required this.vulnerabilityType,
    required this.severity,
    required this.description,
    required this.recommendation,
  });

  /// Default vulnerability scanning patterns covering common issues.
  static List<ScannerPattern> get defaultPatterns => [
        ScannerPattern(
          pattern: r'(?i)password\s*=\s*"[^"]+"',
          vulnerabilityType: VulnerabilityType.hardcodedSecret,
          severity: VulnerabilitySeverity.critical,
          description: 'Hardcoded password detected',
          recommendation:
              'Remove hardcoded password and use secure storage or environment variables.',
        ),
        ScannerPattern(
          pattern: r'(?i)api[_-]?key\s*[:=]\s*"[^"]+"',
          vulnerabilityType: VulnerabilityType.hardcodedSecret,
          severity: VulnerabilitySeverity.critical,
          description: 'Hardcoded API key detected',
          recommendation:
              'Remove hardcoded API key and use secure storage or environment variables.',
        ),
        ScannerPattern(
          pattern: r'(?i)secret\s*[:=]\s*"[^"]+"',
          vulnerabilityType: VulnerabilityType.hardcodedSecret,
          severity: VulnerabilitySeverity.critical,
          description: 'Hardcoded secret detected',
          recommendation:
              'Remove hardcoded secret and use secure storage or environment variables.',
        ),
        ScannerPattern(
          pattern: r'(?i)token\s*[:=]\s*"[A-Za-z0-9\._\-]{20,}"',
          vulnerabilityType: VulnerabilityType.hardcodedSecret,
          severity: VulnerabilitySeverity.high,
          description: 'Hardcoded token detected',
          recommendation: 'Remove hardcoded token and use secure token storage.',
        ),
        ScannerPattern(
          pattern: r'eval\(|Function\.apply\(',
          vulnerabilityType: VulnerabilityType.weakCryptography,
          severity: VulnerabilitySeverity.high,
          description: 'Dynamic code execution detected',
          recommendation: 'Remove dynamic code execution and use static dispatch.',
        ),
        ScannerPattern(
          pattern: r'MD5\.|SHA1\.',
          vulnerabilityType: VulnerabilityType.weakCryptography,
          severity: VulnerabilitySeverity.medium,
          description: 'Deprecated cryptographic algorithm detected',
          recommendation: 'Replace MD5/SHA1 with SHA-256 or stronger algorithm.',
        ),
        ScannerPattern(
          pattern: r'(?i)http://[^"\s]+',
          vulnerabilityType: VulnerabilityType.insecureTransport,
          severity: VulnerabilitySeverity.medium,
          description: 'Insecure HTTP URL detected',
          recommendation: 'Use HTTPS instead of HTTP for all network communications.',
        ),
        ScannerPattern(
          pattern: r'(?i)trustAll|trustAllCertificates|bypassCertificateValidation',
          vulnerabilityType: VulnerabilityType.insecureTransport,
          severity: VulnerabilitySeverity.high,
          description: 'Certificate validation bypass detected',
          recommendation:
              'Remove certificate validation bypass and use proper certificate pinning.',
        ),
      ];
}
