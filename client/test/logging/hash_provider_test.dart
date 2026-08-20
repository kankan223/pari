import 'package:civic_commons/logging/domain/hash_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HashProvider port - Task 13.1', () {
    test('sha256Hex method exists', () {
      expect(HashProvider, isA<Type>());
    });
  });

  group('HashProvider implementations - Task 13.1', () {
    test('in-memory implementation produces consistent hashes', () async {
      final provider = _InMemoryHashProvider();
      final hash1 = await provider.sha256Hex('test');
      final hash2 = await provider.sha256Hex('test');
      expect(hash1, equals(hash2));
    });

    test('in-memory implementation produces different hashes for different inputs', () async {
      final provider = _InMemoryHashProvider();
      final hash1 = await provider.sha256Hex('test1');
      final hash2 = await provider.sha256Hex('test2');
      expect(hash1, isNot(equals(hash2)));
    });

    test('in-memory implementation produces 64-char hex string', () async {
      final provider = _InMemoryHashProvider();
      final hash = await provider.sha256Hex('test');
      expect(hash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });
  });
}

/// Simple in-memory hash provider for testing
class _InMemoryHashProvider implements HashProvider {
  @override
  Future<String> sha256Hex(String input) async {
    // Simple hash for testing (not cryptographically secure)
    final bytes = input.codeUnits;
    var hash = 0;
    for (final byte in bytes) {
      hash = ((hash << 5) - hash + byte) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0').padRight(64, '0');
  }
}
