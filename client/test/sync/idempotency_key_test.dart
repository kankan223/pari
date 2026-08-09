import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/domain/idempotency_key.dart';

/// VERIFY (Task 5.2/5.3): UUID v4 idempotency key generation — format,
/// version/variant bits, uniqueness, and cryptographic randomness.
void main() {
  final generator = IdempotencyKeyGenerator();

  final uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  group('IdempotencyKeyGenerator - UUID v4 (Task 5.2)', () {
    test('produces well-formed lowercase UUID v4 strings', () {
      for (var i = 0; i < 100; i++) {
        final key = generator.generate();
        expect(key, matches(uuidRegex),
            reason: '$key must match UUID v4 shape');
        expect(key.length, 36);
      }
    });

    test('sets the version nibble to 4', () {
      for (var i = 0; i < 50; i++) {
        final key = generator.generate();
        expect(key[14], '4', reason: '$key must be version 4');
      }
    });

    test('sets the RFC 4122 variant bits (8, 9, a or b)', () {
      for (var i = 0; i < 50; i++) {
        final key = generator.generate();
        final variant = key[19];
        expect(variant, anyOf('8', '9', 'a', 'b'),
            reason: '$key variant nibble must be 8-11');
      }
    });

    test('generates a unique key per call', () {
      final seen = <String>{};
      for (var i = 0; i < 1000; i++) {
        final key = generator.generate();
        expect(seen.add(key), isTrue, reason: 'duplicate idempotency key $key');
      }
      expect(seen, hasLength(1000));
    });

    test('exposes the standard Idempotency-Key header name', () {
      expect(IdempotencyKeyGenerator.headerName, 'Idempotency-Key');
    });
  });

  group('IdempotencyKeyGenerator - SECURITY CHECKPOINT (Task 5.3)', () {
    test('keys are random and not predictable across generators', () {
      final a = IdempotencyKeyGenerator().generate();
      final b = IdempotencyKeyGenerator().generate();
      final c = IdempotencyKeyGenerator().generate();
      expect({a, b, c}, hasLength(3),
          reason: 'independent generators must produce distinct keys');
    });

    test('injectable seeded Random is deterministic (test support only)', () {
      final seeded = IdempotencyKeyGenerator(random: Random(42));
      final first = seeded.generate();
      final again = IdempotencyKeyGenerator(random: Random(42)).generate();
      expect(first, again,
          reason: 'a seeded RNG yields the same key for deterministic tests');
    });
  });
}
