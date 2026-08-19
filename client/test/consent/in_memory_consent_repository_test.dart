import 'package:civic_commons/consent/data/in_memory_consent_repository.dart';
import 'package:civic_commons/consent/domain/consent_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryConsentRepository', () {
    late InMemoryConsentRepository repo;

    setUp(() {
      repo = InMemoryConsentRepository();
    });

    test('getConsent returns null for un-granted type', () async {
      final record = await repo.getConsent(ConsentType.coreFunctionality);
      expect(record, isNull);
    });

    test('hasConsent returns false for un-granted type', () async {
      expect(await repo.hasConsent(ConsentType.coreFunctionality), false);
    });

    test('grantConsent stores a granted record', () async {
      await repo.grantConsent(
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        textHash: 'hash_1',
      );

      final record = await repo.getConsent(ConsentType.coreFunctionality);
      expect(record, isNotNull);
      expect(record!.granted, true);
      expect(record.type, ConsentType.coreFunctionality);
      expect(record.consentVersion, '1.0');
      expect(record.textHash, 'hash_1');
      expect(await repo.hasConsent(ConsentType.coreFunctionality), true);
    });

    test('withdrawConsent sets granted to false', () async {
      await repo.grantConsent(
        type: ConsentType.civicEngagement,
        consentVersion: '1.0',
        textHash: 'hash_2',
      );
      expect(await repo.hasConsent(ConsentType.civicEngagement), true);

      await repo.withdrawConsent(ConsentType.civicEngagement);
      final record = await repo.getConsent(ConsentType.civicEngagement);
      expect(record, isNotNull);
      expect(record!.granted, false);
      expect(await repo.hasConsent(ConsentType.civicEngagement), false);
    });

    test('withdrawConsent on un-granted type is no-op', () async {
      await repo.withdrawConsent(ConsentType.analytics);
      expect(await repo.hasConsent(ConsentType.analytics), false);
    });

    test('getAllConsents returns all granted consents newest-first', () async {
      await repo.grantConsent(
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        textHash: 'h1',
      );
      await Future.delayed(const Duration(milliseconds: 5));
      await repo.grantConsent(
        type: ConsentType.analytics,
        consentVersion: '1.0',
        textHash: 'h2',
      );

      final all = await repo.getAllConsents();
      expect(all.length, 2);
      expect(all.first.timestamp.isAfter(all.last.timestamp), true);
    });

    test('hasAllRequiredConsents returns true when all required granted',
        () async {
      for (final type in ConsentType.values) {
        await repo.grantConsent(
          type: type,
          consentVersion: '1.0',
          textHash: 'h',
        );
      }
      expect(await repo.hasAllRequiredConsents(), true);
    });

    test('hasAllRequiredConsents returns false when optional only', () async {
      // Grant only analytics (optional)
      await repo.grantConsent(
        type: ConsentType.analytics,
        consentVersion: '1.0',
        textHash: 'h',
      );
      expect(await repo.hasAllRequiredConsents(), false);
    });

    test('deleteUserData clears all consents and triggers callback', () async {
      var callbackFired = false;
      repo = InMemoryConsentRepository(
        onDataDeleted: () => callbackFired = true,
      );

      await repo.grantConsent(
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        textHash: 'h',
      );
      await repo.deleteUserData();

      expect(callbackFired, true);
      expect(await repo.hasConsent(ConsentType.coreFunctionality), false);
      expect(repo.wasDataDeleted, true);
    });

    test('currentConsentVersion returns 1.0', () {
      expect(repo.currentConsentVersion, '1.0');
    });

    test('grant overwrites previous consent for same type', () async {
      await repo.grantConsent(
        type: ConsentType.educationalContent,
        consentVersion: '1.0',
        textHash: 'h1',
      );
      await repo.grantConsent(
        type: ConsentType.educationalContent,
        consentVersion: '2.0',
        textHash: 'h2',
      );

      final record = await repo.getConsent(ConsentType.educationalContent);
      expect(record!.consentVersion, '2.0');
      expect(record.textHash, 'h2');
    });
  });
}
