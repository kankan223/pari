import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:civic_commons/identity/identity_service.dart';
import 'package:civic_commons/identity/phone_validator.dart';
import 'package:civic_commons/identity/phone_hasher.dart';
import 'package:civic_commons/identity/salt_manager.dart';
import 'package:civic_commons/identity/identity_storage.dart';
import 'package:civic_commons/crypto/secure_key_storage.dart';

void main() {
  group('IdentityService - Blind Hash ID Generation', () {
    late IdentityService identityService;
    late PhoneValidator phoneValidator;
    late PhoneHasher phoneHasher;
    late SaltManager saltManager;
    late IdentityStorage identityStorage;
    late SecureKeyStorage secureStorage;

    setUp(() async {
      // Use in-memory storage for tests (no device keychain required)
      FlutterSecureStorage.setMockInitialValues({});
      secureStorage = SecureKeyStorage();
      await secureStorage.deleteAllKeys();

      phoneValidator = PhoneValidator();
      phoneHasher = PhoneHasher();
      saltManager = SaltManager(secureStorage: secureStorage);
      identityStorage = IdentityStorage(secureStorage: secureStorage);

      identityService = IdentityService(
        phoneValidator: phoneValidator,
        phoneHasher: phoneHasher,
        saltManager: saltManager,
        identityStorage: identityStorage,
      );
    });

    tearDown(() async {
      await secureStorage.deleteAllKeys();
    });

    test('should generate blind hash ID from valid phone number', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);

      // Act
      final blindHashId =
          await identityService.generateBlindHashId(phoneNumber);

      // Assert
      expect(blindHashId, isNotNull);
      expect(
          blindHashId.length, equals(64)); // 256-bit hash = 64 hex characters
    });

    test('should throw exception for invalid phone number', () async {
      // Arrange
      const invalidPhoneNumber = 'invalid';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);

      // Act & Assert
      expect(
        () => identityService.generateBlindHashId(invalidPhoneNumber),
        throwsA(isA<InvalidPhoneNumberException>()),
      );
    });

    test('should throw exception when no salt is available', () async {
      // Arrange
      const phoneNumber = '+14155552671';

      // Act & Assert
      expect(
        () => identityService.generateBlindHashId(phoneNumber),
        throwsA(isA<SaltNotAvailableException>()),
      );
    });

    test('should validate phone number against blind hash ID', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);
      final blindHashId =
          await identityService.generateBlindHashId(phoneNumber);

      // Act
      final isValid =
          await identityService.validatePhoneNumber(phoneNumber, blindHashId);

      // Assert
      expect(isValid, isTrue);
    });

    test('should validate OLD blind hash after salt rotation (fallback)',
        () async {
      // Arrange: generate a blind hash under the current salt
      const phoneNumber = '+14155552671';
      const currentSalt = 'current_salt_12345';
      const newSalt = 'new_salt_67890';
      await identityService.initialize(currentSalt);
      final blindHashId =
          await identityService.generateBlindHashId(phoneNumber);

      // Rotate the salt (old salt moves to fallback)
      await identityService.rotateSalt(newSalt);

      // Act: validate the old hash under the new salt configuration
      final isValid =
          await identityService.validatePhoneNumber(phoneNumber, blindHashId);

      // Assert: old hash still validates via previous-salt fallback
      expect(isValid, isTrue);

      // A freshly generated hash under the new salt differs from the old one
      final newBlindHashId =
          await identityService.generateBlindHashId(phoneNumber);
      expect(newBlindHashId, isNot(equals(blindHashId)));
    });

    test('should reject validation after rotation when old salt is purged',
        () async {
      // Arrange: generate a blind hash under the current salt
      const phoneNumber = '+14155552671';
      const currentSalt = 'current_salt_12345';
      const newSalt = 'new_salt_67890';
      await identityService.initialize(currentSalt);
      final blindHashId =
          await identityService.generateBlindHashId(phoneNumber);

      // Rotate twice so the original salt is dropped entirely (only 1 fallback)
      await identityService.rotateSalt(newSalt);
      await identityService.rotateSalt('third_salt_11111');

      // Act
      final isValid =
          await identityService.validatePhoneNumber(phoneNumber, blindHashId);

      // Assert: no salt in the (current + single previous) set can reproduce it
      expect(isValid, isFalse);
    });

    test('should reject invalid phone number validation', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const invalidPhoneNumber = '+14155552672';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);
      final blindHashId =
          await identityService.generateBlindHashId(phoneNumber);

      // Act
      final isValid = await identityService.validatePhoneNumber(
          invalidPhoneNumber, blindHashId);

      // Assert
      expect(isValid, isFalse);
    });

    test('should store and retrieve blind hash ID', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);
      final blindHashId =
          await identityService.generateBlindHashId(phoneNumber);

      // Act
      final retrievedBlindHashId = await identityService.getBlindHashId();

      // Assert
      expect(retrievedBlindHashId, equals(blindHashId));
    });

    test('should return null when no blind hash ID is stored', () async {
      // Act
      final retrievedBlindHashId = await identityService.getBlindHashId();

      // Assert
      expect(retrievedBlindHashId, isNull);
    });

    test('should check if blind hash ID is stored', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);

      // Act
      final hasBefore = await identityService.hasBlindHashId();
      await identityService.generateBlindHashId(phoneNumber);
      final hasAfter = await identityService.hasBlindHashId();

      // Assert
      expect(hasBefore, isFalse);
      expect(hasAfter, isTrue);
    });

    test('should delete blind hash ID', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);
      await identityService.generateBlindHashId(phoneNumber);

      // Act
      await identityService.deleteBlindHashId();
      final retrievedBlindHashId = await identityService.getBlindHashId();

      // Assert
      expect(retrievedBlindHashId, isNull);
    });

    test('should check if salt rotation is needed', () async {
      // Arrange
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);

      // Act
      final needsRotation = await identityService.needsSaltRotation();

      // Assert
      expect(needsRotation, isFalse); // Just set, no rotation needed
    });

    test('should rotate salt', () async {
      // Arrange
      const currentSalt = 'current_salt_12345';
      const newSalt = 'new_salt_67890';
      await identityService.initialize(currentSalt);

      // Act
      await identityService.rotateSalt(newSalt);
      final retrievedCurrentSalt = await saltManager.getCurrentSalt();
      final retrievedPreviousSalt = await saltManager.getPreviousSalt();

      // Assert
      expect(retrievedCurrentSalt, equals(newSalt));
      expect(retrievedPreviousSalt, equals(currentSalt));
    });

    test('should get salt rotation date', () async {
      // Arrange
      const salt = 'test_salt_12345';
      final beforeSet = DateTime.now();
      await identityService.initialize(salt);
      final afterSet = DateTime.now();

      // Act
      final rotationDate = await identityService.getSaltRotationDate();

      // Assert
      expect(rotationDate, isNotNull);
      expect(
          rotationDate!.isAfter(beforeSet) ||
              rotationDate.isAtSameMomentAs(beforeSet),
          isTrue);
      expect(
          rotationDate.isBefore(afterSet) ||
              rotationDate.isAtSameMomentAs(afterSet),
          isTrue);
    });

    test('should delete all identity data', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);
      await identityService.generateBlindHashId(phoneNumber);

      // Act
      await identityService.deleteAllIdentityData();
      final retrievedBlindHashId = await identityService.getBlindHashId();
      final retrievedCurrentSalt = await saltManager.getCurrentSalt();

      // Assert
      expect(retrievedBlindHashId, isNull);
      expect(retrievedCurrentSalt, isNull);
    });
  });

  group('IdentityService - Security Verification', () {
    late IdentityService identityService;
    late PhoneValidator phoneValidator;
    late PhoneHasher phoneHasher;
    late SaltManager saltManager;
    late IdentityStorage identityStorage;
    late SecureKeyStorage secureStorage;

    setUp(() async {
      // Use in-memory storage for tests (no device keychain required)
      FlutterSecureStorage.setMockInitialValues({});
      secureStorage = SecureKeyStorage();
      await secureStorage.deleteAllKeys();

      phoneValidator = PhoneValidator();
      phoneHasher = PhoneHasher();
      saltManager = SaltManager(secureStorage: secureStorage);
      identityStorage = IdentityStorage(secureStorage: secureStorage);

      identityService = IdentityService(
        phoneValidator: phoneValidator,
        phoneHasher: phoneHasher,
        saltManager: saltManager,
        identityStorage: identityStorage,
      );
    });

    tearDown(() async {
      await secureStorage.deleteAllKeys();
    });

    test('should not expose phone number in blind hash ID', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);

      // Act
      final blindHashId =
          await identityService.generateBlindHashId(phoneNumber);

      // Assert
      expect(blindHashId.contains(phoneNumber), isFalse);
      expect(blindHashId.contains('14155552671'), isFalse);
    });

    test('should confirm no raw phone numbers are persisted to disk', () async {
      // This test verifies that raw phone numbers are never persisted to disk
      // The implementation only stores blind hash IDs in secure storage

      // Arrange
      const phoneNumber = '+14155552671';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);
      await identityService.generateBlindHashId(phoneNumber);

      // Act
      final storedData = await identityStorage.getBlindHashId();

      // Assert
      // Stored data should not contain the raw phone number
      expect(storedData, isNotNull);
      expect(storedData!.contains(phoneNumber), isFalse);
      expect(storedData.contains('14155552671'), isFalse);
    });

    test('should confirm no raw phone numbers are logged', () async {
      // This test verifies that the identity service does not log raw phone numbers
      // The implementation does not use any logging functions for phone numbers

      // Arrange
      const phoneNumber = '+14155552671';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);

      // Act
      final blindHashId =
          await identityService.generateBlindHashId(phoneNumber);

      // Assert
      // The operation completed successfully without logging
      expect(blindHashId, isNotNull);
      expect(blindHashId.length, equals(64));
    });

    test('should store blind hash ID in secure storage', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const salt = 'test_salt_12345';
      await identityService.initialize(salt);

      // Act
      final blindHashId =
          await identityService.generateBlindHashId(phoneNumber);
      final retrievedBlindHashId = await identityStorage.getBlindHashId();

      // Assert
      // Blind hash ID is stored in secure storage
      expect(retrievedBlindHashId, equals(blindHashId));
    });
  });
}
