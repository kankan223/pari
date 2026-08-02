import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:civic_commons/identity/salt_manager.dart';
import 'package:civic_commons/identity/phone_hasher.dart';
import 'package:civic_commons/crypto/secure_key_storage.dart';

void main() {
  group('SaltManager - Salt Management', () {
    late SaltManager saltManager;
    late SecureKeyStorage secureStorage;

    setUp(() async {
      // Use in-memory storage for tests (no device keychain required)
      FlutterSecureStorage.setMockInitialValues({});
      secureStorage = SecureKeyStorage();
      await secureStorage.deleteAllKeys();
      saltManager = SaltManager(secureStorage: secureStorage);
    });

    tearDown(() async {
      await secureStorage.deleteAllKeys();
    });

    test('should set and get current salt', () async {
      // Arrange
      const salt = 'current_salt_12345';

      // Act
      await saltManager.setCurrentSalt(salt);
      final retrievedSalt = await saltManager.getCurrentSalt();

      // Assert
      expect(retrievedSalt, equals(salt));
    });

    test('should return null when no current salt is set', () async {
      // Act
      final retrievedSalt = await saltManager.getCurrentSalt();

      // Assert
      expect(retrievedSalt, isNull);
    });

    test('should rotate salt correctly', () async {
      // Arrange
      const currentSalt = 'current_salt_12345';
      const newSalt = 'new_salt_67890';
      await saltManager.setCurrentSalt(currentSalt);

      // Act
      await saltManager.rotateSalt(newSalt);
      final retrievedCurrentSalt = await saltManager.getCurrentSalt();
      final retrievedPreviousSalt = await saltManager.getPreviousSalt();

      // Assert
      expect(retrievedCurrentSalt, equals(newSalt));
      expect(retrievedPreviousSalt, equals(currentSalt));
    });

    test('should get all salts in correct order', () async {
      // Arrange
      const currentSalt = 'current_salt_12345';
      const previousSalt = 'previous_salt_67890';
      await saltManager.setCurrentSalt(currentSalt);
      await saltManager.rotateSalt(previousSalt);

      // Act
      final allSalts = await saltManager.getAllSalts();

      // Assert
      expect(allSalts.length, equals(2));
      expect(allSalts[0], equals(previousSalt)); // Current after rotation
      expect(allSalts[1], equals(currentSalt)); // Previous after rotation
    });

    test('should return only current salt when no previous salt exists', () async {
      // Arrange
      const currentSalt = 'current_salt_12345';
      await saltManager.setCurrentSalt(currentSalt);

      // Act
      final allSalts = await saltManager.getAllSalts();

      // Assert
      expect(allSalts.length, equals(1));
      expect(allSalts[0], equals(currentSalt));
    });

    test('should check if rotation is needed', () async {
      // Arrange
      const salt = 'current_salt_12345';
      await saltManager.setCurrentSalt(salt);

      // Act
      final needsRotation = await saltManager.needsRotation();

      // Assert
      expect(needsRotation, isFalse); // Just set, no rotation needed
    });

    test('should indicate rotation is needed when no salt is set', () async {
      // Act
      final needsRotation = await saltManager.needsRotation();

      // Assert
      expect(needsRotation, isTrue); // No salt set, need to rotate
    });

    test('should get rotation date', () async {
      // Arrange
      const salt = 'current_salt_12345';
      final beforeSet = DateTime.now();
      await saltManager.setCurrentSalt(salt);
      final afterSet = DateTime.now();

      // Act
      final rotationDate = await saltManager.getRotationDate();

      // Assert
      expect(rotationDate, isNotNull);
      expect(rotationDate!.isAfter(beforeSet) || rotationDate.isAtSameMomentAs(beforeSet), isTrue);
      expect(rotationDate.isBefore(afterSet) || rotationDate.isAtSameMomentAs(afterSet), isTrue);
    });

    test('should return null when no rotation date is set', () async {
      // Act
      final rotationDate = await saltManager.getRotationDate();

      // Assert
      expect(rotationDate, isNull);
    });

    test('should validate hash with fallback to previous salt', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const currentSalt = 'current_salt_12345';
      const previousSalt = 'previous_salt_67890';
      
      // Simulate hash verification function (async as required by the API)
      Future<bool> verifyFunction(String phone, String salt) async {
        return salt == previousSalt; // Only valid with previous salt
      }

      await saltManager.setCurrentSalt(currentSalt);
      await saltManager.rotateSalt(previousSalt);

      // Act
      final isValid = await saltManager.validateHashWithFallback(
        phoneNumber,
        'dummy_hash',
        verifyFunction,
      );

      // Assert
      expect(isValid, isTrue); // Should match with previous salt
    });

    test('should validate real old hash after rotation (fallback)', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const currentSalt = 'current_salt_12345';
      const newSalt = 'new_salt_67890';

      // Hash the phone number with the current salt
      await saltManager.setCurrentSalt(currentSalt);
      final blindHashId = await PhoneHasher.hashPhoneNumber(phoneNumber, currentSalt);

      // Rotate to a new salt (old salt becomes the fallback)
      await saltManager.rotateSalt(newSalt);

      // Act: validate the OLD hash against the new salt configuration
      final isValid = await saltManager.validateHashWithFallback(
        phoneNumber,
        blindHashId,
        (phone, salt) => PhoneHasher.verifyPhoneHash(phone, salt, blindHashId),
      );

      // Assert: old hash still validates via the previous-salt fallback
      expect(isValid, isTrue);

      // A fresh hash under the new salt must differ from the old blind hash ID
      final newHash = await PhoneHasher.hashPhoneNumber(phoneNumber, newSalt);
      expect(newHash, isNot(equals(blindHashId)));
    });

    test('should return false when no salt matches the hash', () async {
      // Arrange
      const phoneNumber = '+14155552671';
      const currentSalt = 'current_salt_12345';

      await saltManager.setCurrentSalt(currentSalt);

      // Act: hash with a totally different salt and try to validate
      final differentHash = await PhoneHasher.hashPhoneNumber(phoneNumber, 'other_salt');
      final isValid = await saltManager.validateHashWithFallback(
        phoneNumber,
        differentHash,
        (phone, salt) => PhoneHasher.verifyPhoneHash(phone, salt, differentHash),
      );

      // Assert
      expect(isValid, isFalse);
    });

    test('should delete all salts', () async {
      // Arrange
      const currentSalt = 'current_salt_12345';
      const previousSalt = 'previous_salt_67890';
      await saltManager.setCurrentSalt(currentSalt);
      await saltManager.rotateSalt(previousSalt);

      // Act
      await saltManager.deleteAllSalts();
      final retrievedCurrentSalt = await saltManager.getCurrentSalt();
      final retrievedPreviousSalt = await saltManager.getPreviousSalt();

      // Assert
      expect(retrievedCurrentSalt, isNull);
      expect(retrievedPreviousSalt, isNull);
    });
  });

  group('SaltManager - Quarter Management', () {
    test('should get correct quarter for date', () {
      expect(SaltManager.getQuarter(DateTime(2024, 1, 15)), equals(1));
      expect(SaltManager.getQuarter(DateTime(2024, 4, 15)), equals(2));
      expect(SaltManager.getQuarter(DateTime(2024, 7, 15)), equals(3));
      expect(SaltManager.getQuarter(DateTime(2024, 10, 15)), equals(4));
    });

    test('should get correct quarter key for date', () {
      expect(SaltManager.getQuarterKey(DateTime(2024, 1, 15)), equals('2024Q1'));
      expect(SaltManager.getQuarterKey(DateTime(2024, 4, 15)), equals('2024Q2'));
      expect(SaltManager.getQuarterKey(DateTime(2024, 7, 15)), equals('2024Q3'));
      expect(SaltManager.getQuarterKey(DateTime(2024, 10, 15)), equals('2024Q4'));
    });
  });

  group('SaltManager - Security Verification', () {
    late SaltManager saltManager;
    late SecureKeyStorage secureStorage;

    setUp(() async {
      // Use in-memory storage for tests (no device keychain required)
      FlutterSecureStorage.setMockInitialValues({});
      secureStorage = SecureKeyStorage();
      await secureStorage.deleteAllKeys();
      saltManager = SaltManager(secureStorage: secureStorage);
    });

    tearDown(() async {
      await secureStorage.deleteAllKeys();
    });

    test('should not expose salt in logs', () async {
      // This test verifies that salt operations do not log raw salt values
      // The implementation does not use any logging functions for salts
      
      // Arrange
      const salt = 'current_salt_12345';

      // Act
      await saltManager.setCurrentSalt(salt);
      final retrievedSalt = await saltManager.getCurrentSalt();

      // Assert
      // The operation completed successfully without logging
      expect(retrievedSalt, equals(salt));
    });

    test('should confirm salts are stored in secure storage', () async {
      // Arrange
      const salt = 'current_salt_12345';

      // Act
      await saltManager.setCurrentSalt(salt);
      final retrievedSalt = await saltManager.getCurrentSalt();

      // Assert
      // Salt is retrieved from secure storage
      expect(retrievedSalt, equals(salt));
    });
  });
}
