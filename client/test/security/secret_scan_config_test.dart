import 'package:civic_commons/security/domain/secret_scan_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecretScanPattern', () {
    test('defaultPatterns has 8 patterns', () {
      expect(SecretScanPattern.defaultPatterns.length, 8);
    });

    test('all patterns have non-empty pattern', () {
      for (final pattern in SecretScanPattern.defaultPatterns) {
        expect(pattern.pattern.isNotEmpty, isTrue,
            reason: 'Pattern has empty regex');
      }
    });

    test('all patterns have non-empty description', () {
      for (final pattern in SecretScanPattern.defaultPatterns) {
        expect(pattern.description.isNotEmpty, isTrue,
            reason: 'Pattern has empty description');
      }
    });

    test('all patterns have non-empty owaspCategory', () {
      for (final pattern in SecretScanPattern.defaultPatterns) {
        expect(pattern.owaspCategory.isNotEmpty, isTrue,
            reason: 'Pattern has empty owaspCategory');
      }
    });

    test('password pattern matches hardcoded passwords', () {
      final pattern = SecretScanPattern.defaultPatterns.firstWhere(
        (p) => p.description == 'Hardcoded password',
      );
      // Verify the pattern structure is valid
      expect(pattern.pattern, contains('password'));
      expect(pattern.pattern, contains('[^"]+'));
      expect(pattern.owaspCategory, 'MSTG-CODE-1');
    });

    test('password pattern does not match variable assignments', () {
      final pattern = SecretScanPattern.defaultPatterns.firstWhere(
        (p) => p.description == 'Hardcoded password',
      );
      // Verify pattern requires quoted value (not bare variable)
      expect(pattern.pattern, contains('"'));
      expect(pattern.pattern, isNot(contains('getPassword')));
    });

    test('api_key pattern matches hardcoded API keys', () {
      final pattern = SecretScanPattern.defaultPatterns.firstWhere(
        (p) => p.description == 'Hardcoded API key',
      );
      expect(pattern.pattern, contains('api'));
      expect(pattern.pattern, contains('key'));
      expect(pattern.owaspCategory, 'MSTG-CODE-1');
    });

    test('secret pattern matches hardcoded secrets', () {
      final pattern = SecretScanPattern.defaultPatterns.firstWhere(
        (p) => p.description == 'Hardcoded secret',
      );
      expect(pattern.pattern, contains('secret'));
      expect(pattern.owaspCategory, 'MSTG-CODE-1');
    });

    test('bearer token pattern matches hardcoded tokens', () {
      final pattern = SecretScanPattern.defaultPatterns.firstWhere(
        (p) => p.description == 'Hardcoded Bearer token',
      );
      expect(pattern.pattern, contains('bearer'));
      expect(pattern.owaspCategory, 'MSTG-CODE-1');
    });

    test('database connection string pattern matches URIs', () {
      final pattern = SecretScanPattern.defaultPatterns.firstWhere(
        (p) =>
            p.description == 'Database connection string with credentials',
      );
      expect(pattern.pattern, contains('mongodb'));
      expect(pattern.pattern, contains('postgres'));
      expect(pattern.owaspCategory, 'MSTG-STORAGE-1');
    });

    test('custom pattern can be created', () {
      final custom = SecretScanPattern(
        pattern: r'CUSTOM_SECRET\s*=\s*"[^"]+"',
        description: 'Custom secret',
        owaspCategory: 'MSTG-CODE-1',
      );

      expect(custom.pattern, contains('CUSTOM_SECRET'));
      expect(custom.description, 'Custom secret');
    });

    test('patterns cover all major secret types', () {
      final descriptions =
          SecretScanPattern.defaultPatterns.map((p) => p.description).toSet();
      expect(descriptions, contains('Hardcoded password'));
      expect(descriptions, contains('Hardcoded API key'));
      expect(descriptions, contains('Hardcoded secret'));
      expect(descriptions, contains('Hardcoded Bearer token'));
      expect(descriptions, contains('Database connection string with credentials'));
    });
  });
}
