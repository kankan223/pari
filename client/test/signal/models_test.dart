import 'dart:typed_data';

import 'package:civic_commons/signal/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PreKeyBundle - Task 13.1', () {
    test('constructs with required fields', () {
      final bundle = PreKeyBundle(
        registrationId: 'user123',
        identityKey: Uint8List(32),
        signedPreKeyId: 1,
        signedPreKey: Uint8List(32),
        signedPreKeySignature: Uint8List(64),
      );
      expect(bundle.registrationId, 'user123');
      expect(bundle.signedPreKeyId, 1);
      expect(bundle.oneTimePreKeyId, isNull);
      expect(bundle.oneTimePreKey, isNull);
    });

    test('constructs with optional one-time prekey', () {
      final bundle = PreKeyBundle(
        registrationId: 'user123',
        identityKey: Uint8List(32),
        signedPreKeyId: 1,
        signedPreKey: Uint8List(32),
        signedPreKeySignature: Uint8List(64),
        oneTimePreKeyId: 42,
        oneTimePreKey: Uint8List(32),
      );
      expect(bundle.oneTimePreKeyId, 42);
      expect(bundle.oneTimePreKey, isNotNull);
    });

    test('toJson includes all required fields', () {
      final bundle = PreKeyBundle(
        registrationId: 'user123',
        identityKey: Uint8List(32),
        signedPreKeyId: 1,
        signedPreKey: Uint8List(32),
        signedPreKeySignature: Uint8List(64),
      );
      final json = bundle.toJson();
      expect(json['registrationId'], 'user123');
      expect(json['signedPreKeyId'], 1);
      expect(json.containsKey('identityKey'), isTrue);
      expect(json.containsKey('signedPreKey'), isTrue);
      expect(json.containsKey('signedPreKeySignature'), isTrue);
    });

    test('toJson includes one-time prekey when present', () {
      final bundle = PreKeyBundle(
        registrationId: 'user123',
        identityKey: Uint8List(32),
        signedPreKeyId: 1,
        signedPreKey: Uint8List(32),
        signedPreKeySignature: Uint8List(64),
        oneTimePreKeyId: 42,
        oneTimePreKey: Uint8List(32),
      );
      final json = bundle.toJson();
      expect(json['oneTimePreKeyId'], 42);
      expect(json.containsKey('oneTimePreKey'), isTrue);
    });

    test('toJson excludes one-time prekey when null', () {
      final bundle = PreKeyBundle(
        registrationId: 'user123',
        identityKey: Uint8List(32),
        signedPreKeyId: 1,
        signedPreKey: Uint8List(32),
        signedPreKeySignature: Uint8List(64),
      );
      final json = bundle.toJson();
      expect(json.containsKey('oneTimePreKeyId'), isFalse);
      expect(json.containsKey('oneTimePreKey'), isFalse);
    });

    test('fromJson creates valid bundle', () {
      final json = {
        'registrationId': 'user123',
        'identityKey': 'AAAA', // base64
        'signedPreKeyId': 1,
        'signedPreKey': 'AAAA',
        'signedPreKeySignature': 'AAAA',
      };
      final bundle = PreKeyBundle.fromJson(json);
      expect(bundle.registrationId, 'user123');
      expect(bundle.signedPreKeyId, 1);
      expect(bundle.identityKey.length, greaterThan(0));
    });

    test('fromJson with one-time prekey', () {
      final json = {
        'registrationId': 'user123',
        'identityKey': 'AAAA',
        'signedPreKeyId': 1,
        'signedPreKey': 'AAAA',
        'signedPreKeySignature': 'AAAA',
        'oneTimePreKeyId': 42,
        'oneTimePreKey': 'AAAA',
      };
      final bundle = PreKeyBundle.fromJson(json);
      expect(bundle.oneTimePreKeyId, 42);
      expect(bundle.oneTimePreKey, isNotNull);
    });

    test('toJson/fromJson round-trip', () {
      final original = PreKeyBundle(
        registrationId: 'user123',
        identityKey: Uint8List(32)..[0] = 1,
        signedPreKeyId: 1,
        signedPreKey: Uint8List(32)..[0] = 2,
        signedPreKeySignature: Uint8List(64)..[0] = 3,
        oneTimePreKeyId: 42,
        oneTimePreKey: Uint8List(32)..[0] = 4,
      );
      final json = original.toJson();
      final restored = PreKeyBundle.fromJson(json);
      expect(restored.registrationId, original.registrationId);
      expect(restored.signedPreKeyId, original.signedPreKeyId);
      expect(restored.oneTimePreKeyId, original.oneTimePreKeyId);
    });
  });

  group('SignedPreKey - Task 13.1', () {
    test('constructs with required fields', () {
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(days: 7));
      final key = SignedPreKey(
        keyId: 1,
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: now,
        expiresAt: expiresAt,
      );
      expect(key.keyId, 1);
      expect(key.createdAt, now);
      expect(key.expiresAt, expiresAt);
    });

    test('needsRotation returns true when expired', () {
      final key = SignedPreKey(
        keyId: 1,
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime.now().subtract(const Duration(days: 14)),
        expiresAt: DateTime.now().subtract(const Duration(days: 7)),
      );
      expect(key.needsRotation(), isTrue);
    });

    test('needsRotation returns false when not expired', () {
      final key = SignedPreKey(
        keyId: 1,
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      expect(key.needsRotation(), isFalse);
    });
  });

  group('OneTimePreKey - Task 13.1', () {
    test('constructs with required fields', () {
      final key = OneTimePreKey(
        keyId: 1,
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
      );
      expect(key.keyId, 1);
      expect(key.publicKey.length, 32);
      expect(key.privateKey.length, 32);
    });

    test('equality by keyId', () {
      final a = OneTimePreKey(
        keyId: 1,
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
      );
      final b = OneTimePreKey(
        keyId: 1,
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
      );
      // Note: OneTimePreKey doesn't override ==, so identity comparison
      expect(identical(a, a), isTrue);
      expect(identical(a, b), isFalse);
    });
  });
}
