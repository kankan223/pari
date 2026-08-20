import 'package:civic_commons/consent/data/in_memory_consent_repository.dart';
import 'package:civic_commons/consent/domain/consent_type.dart';
import 'package:civic_commons/state/data/local_consent_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 13.2 — DPDP Consent lifecycle integration: grant all required
/// consents → verify hasAllRequiredConsents → withdraw one → verify
/// incomplete → delete user data → verify wiped. Uses REAL in-memory
/// stores and the REAL LocalConsentBloc (no fakes).
void main() {
  group('Task 13.2 — consent lifecycle integration', () {
    late InMemoryConsentRepository repo;
    late LocalConsentBloc bloc;

    setUp(() {
      repo = InMemoryConsentRepository();
      bloc = LocalConsentBloc(repository: repo);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('grant all required consents → hasAllRequiredConsents is true',
        () async {
      for (final type in ConsentType.values) {
        await repo.grantConsent(
          type: type,
          consentVersion: '1.0',
          textHash: 'sha256:${type.wireName}',
        );
      }

      expect(await repo.hasAllRequiredConsents(), isTrue);

      for (final type in ConsentType.values) {
        expect(await repo.hasConsent(type), isTrue);
      }
    });

    test('withdraw one required consent → hasAllRequiredConsents becomes false',
        () async {
      for (final type in ConsentType.values) {
        await repo.grantConsent(
          type: type,
          consentVersion: '1.0',
          textHash: 'sha256:${type.wireName}',
        );
      }
      expect(await repo.hasAllRequiredConsents(), isTrue);

      await repo.withdrawConsent(ConsentType.coreFunctionality);
      expect(await repo.hasConsent(ConsentType.coreFunctionality), isFalse);
      expect(await repo.hasAllRequiredConsents(), isFalse);
    });

    test('consent versioning: grant v1.0 then upgrade to v2.0', () async {
      await repo.grantConsent(
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        textHash: 'sha256:v1.0',
      );
      var record = await repo.getConsent(ConsentType.coreFunctionality);
      expect(record!.consentVersion, '1.0');

      await repo.grantConsent(
        type: ConsentType.coreFunctionality,
        consentVersion: '2.0',
        textHash: 'sha256:v2.0',
      );
      record = await repo.getConsent(ConsentType.coreFunctionality);
      expect(record!.consentVersion, '2.0');
      expect(record.textHash, 'sha256:v2.0');
    });

    test('delete user data wipes all consents', () async {
      var dataDeleted = false;
      repo = InMemoryConsentRepository(onDataDeleted: () {
        dataDeleted = true;
      });
      bloc = LocalConsentBloc(repository: repo);

      for (final type in ConsentType.values) {
        await repo.grantConsent(
          type: type,
          consentVersion: '1.0',
          textHash: 'sha256:${type.wireName}',
        );
      }
      expect(await repo.hasAllRequiredConsents(), isTrue);

      await repo.deleteUserData();

      expect(dataDeleted, isTrue);
      expect(await repo.hasAllRequiredConsents(), isFalse);
      expect((await repo.getAllConsents()), isEmpty);
    });

    test('consent audit trail: getAllConsents returns chronological history',
        () async {
      await repo.grantConsent(
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        textHash: 'sha256:cf',
      );
      await Future.delayed(const Duration(milliseconds: 10));
      await repo.withdrawConsent(ConsentType.coreFunctionality);

      final history = await repo.getAllConsents();
      // The withdrawal record should be most recent
      expect(history.first.granted, isFalse);
      expect(history.first.type, ConsentType.coreFunctionality);
    });

    test('bloc exposes consent state via stream', () async {
      final states = <dynamic>[];
      final sub = bloc.state.listen((s) => states.add(s));

      await bloc.refresh();

      expect(states, isNotEmpty);
      expect(bloc.current.consentStatus, isA<Map>());

      await sub.cancel();
    });

    test('zero-PII invariant: no identity fields in consent records', () async {
      await repo.grantConsent(
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        textHash: 'sha256:cf',
      );
      final record = (await repo.getAllConsents()).single;

      final recordStr = record.toString().toLowerCase();
      expect(recordStr, isNot(contains('+91')));
      expect(recordStr, isNot(contains('@')));
      expect(recordStr, isNot(contains('phone')));
    });
  });
}
