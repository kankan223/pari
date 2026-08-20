/// Configuration for secret scanning patterns (Task 13.4).
///
/// Defines the patterns used to detect hardcoded secrets, API keys, tokens,
/// and credentials in source code. Each pattern has a regex, severity, and
/// description for the detected vulnerability type.
class SecretScanPattern {
  /// Regex pattern to match in source code.
  final String pattern;

  /// Description of what this pattern detects.
  final String description;

  /// OWASP category for this type of secret.
  final String owaspCategory;

  const SecretScanPattern({
    required this.pattern,
    required this.description,
    required this.owaspCategory,
  });

  /// Default secret scanning patterns covering common secret types.
  static List<SecretScanPattern> get defaultPatterns => [
        SecretScanPattern(
          pattern: r'(?i)(password|passwd|pwd)\s*[:=]\s*"[^"]+"',
          description: 'Hardcoded password',
          owaspCategory: 'MSTG-CODE-1',
        ),
        SecretScanPattern(
          pattern: r'(?i)(api[_-]?key|apikey)\s*[:=]\s*"[^"]+"',
          description: 'Hardcoded API key',
          owaspCategory: 'MSTG-CODE-1',
        ),
        SecretScanPattern(
          pattern: r'(?i)(secret|client[_-]?secret)\s*[:=]\s*"[^"]+"',
          description: 'Hardcoded secret',
          owaspCategory: 'MSTG-CODE-1',
        ),
        SecretScanPattern(
          pattern: r'(?i)(access[_-]?token|auth[_-]?token)\s*[:=]\s*"[^"]+"',
          description: 'Hardcoded access/auth token',
          owaspCategory: 'MSTG-CODE-1',
        ),
        SecretScanPattern(
          pattern: r'(?i)private[_-]?key\s*[:=]\s*"[^"]+"',
          description: 'Hardcoded private key',
          owaspCategory: 'MSTG-CRYPTO-1',
        ),
        SecretScanPattern(
          pattern: r'(?i)(aws[_-]?access[_-]?key|aws[_-]?secret)',
          description: 'AWS credential',
          owaspCategory: 'MSTG-CODE-1',
        ),
        SecretScanPattern(
          pattern: r'(?i)(bearer\s+[A-Za-z0-9\._\-]{20,})',
          description: 'Hardcoded Bearer token',
          owaspCategory: 'MSTG-CODE-1',
        ),
        SecretScanPattern(
          pattern: r'(?i)(jdbc|mongodb|redis|mysql|postgres)://[^\s]+',
          description: 'Database connection string with credentials',
          owaspCategory: 'MSTG-STORAGE-1',
        ),
      ];
}
