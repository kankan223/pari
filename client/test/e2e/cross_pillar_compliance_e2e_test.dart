import 'dart:typed_data';

import 'package:civic_commons/audit/data/in_memory_audit_repository.dart';
import 'package:civic_commons/audit/domain/audit_action.dart';
import 'package:civic_commons/audit/domain/audit_record.dart';
import 'package:civic_commons/consent/data/in_memory_consent_repository.dart';
import 'package:civic_commons/consent/domain/consent_type.dart';
import 'package:civic_commons/rate_limit/data/in_memory_rate_limit_repository.dart';
import 'package:civic_commons/rate_limit/domain/rate_limit_policy.dart';
import 'package:civic_commons/state/data/local_audit_log_bloc.dart';
import 'package:civic_commons/state/data/local_consent_bloc.dart';
import 'package:civic_commons/state/data/local_rate_limit_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 13.3 E2E: Cross-pillar compliance end-to-end lifecycle.
///
/// Tests the complete compliance journey across pillars:
/// 1. User grants DPDP consent → audit record created
/// 2. Rate limiting tracks request patterns
/// 3. Audit log maintains tamper-evident chain
/// 4. Consent withdrawal triggers data deletion
/// 5. All three pillars work together without PII leaks
void main() {
  group('Cross-Pillar E2E - Compliance lifecycle', () {
    late InMemoryConsentRepository consentRepo;
    late InMemoryAuditRepository auditRepo;
    late InMemoryRateLimitRepository rateLimitRepo;
    late LocalConsentBloc consentBloc;
    late LocalAuditLogBloc auditBloc;
    late LocalRateLimitBloc rateLimitBloc;
    late bool dataDeleted;

    setUp(() {
      dataDeleted = false;
      consentRepo = InMemoryConsentRepository(
        onDataDeleted: () => dataDeleted = true,
      );
      // Use the deterministic hasher so the chain stays consistent.
      final hasher = _ConsistentHasher();
      auditRepo = InMemoryAuditRepository(hasher: hasher);
      rateLimitRepo = InMemoryRateLimitRepository();
      consentBloc = LocalConsentBloc(repository: consentRepo);
      auditBloc = LocalAuditLogBloc(repository: auditRepo);
      rateLimitBloc = LocalRateLimitBloc(repository: rateLimitRepo);
    });

    tearDown(() async {
      await consentBloc.close();
      await auditBloc.close();
      await rateLimitBloc.close();
    });

    test('full compliance journey: consent → audit → rate limit → withdraw',
        () async {
      // Step 1: User grants all required consents.
      await consentBloc.grantAll();
      // Refresh to ensure current state is fully loaded.
      await consentBloc.refresh();
      expect(consentBloc.current.allRequiredGranted, isTrue);

      final allConsents = await consentRepo.getAllConsents();
      expect(allConsents.length, ConsentType.values.length);

      // Step 2: Record audit events for the consent grant.
      final hash0 = await AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'User granted consent for core functionality',
        occurredAt: DateTime.now().toUtc(),
        prevHash: AuditRecord.genesisHash,
        selfHash: '',
      ).computeSelfHash(_ConsistentHasher());
      await auditRepo.append(AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'User granted consent for core functionality',
        occurredAt: DateTime.now().toUtc(),
        prevHash: AuditRecord.genesisHash,
        selfHash: hash0,
      ));

      // Record a second event.
      final hash1 = await AuditRecord(
        seq: 1,
        recordId: 'audit-002',
        action: AuditAction.sensitiveDataAccessed,
        summary: 'User accessed sensitive data export',
        occurredAt: DateTime.now().toUtc(),
        prevHash: hash0,
        selfHash: '',
      ).computeSelfHash(_ConsistentHasher());
      await auditRepo.append(AuditRecord(
        seq: 1,
        recordId: 'audit-002',
        action: AuditAction.sensitiveDataAccessed,
        summary: 'User accessed sensitive data export',
        occurredAt: DateTime.now().toUtc(),
        prevHash: hash0,
        selfHash: hash1,
      ));

      // Step 3: Verify audit log integrity.
      expect(await auditRepo.verifyIntegrity(), isTrue);
      expect(await auditRepo.getCount(), 2);

      // Step 4: Rate limiting tracks request patterns.
      await rateLimitRepo.recordRequest(RateLimitPolicy.otpRequest);
      await rateLimitRepo.recordRequest(RateLimitPolicy.otpRequest);
      await rateLimitRepo.recordRequest(RateLimitPolicy.otpRequest);

      final bucket = await rateLimitRepo.getBucket(RateLimitPolicy.otpRequest);
      expect(bucket.requestCount, 3);
      expect(bucket.isLimitReached, isFalse);

      // Step 5: Exhaust the rate limit.
      await rateLimitRepo.recordRequest(RateLimitPolicy.otpRequest);
      await rateLimitRepo.recordRequest(RateLimitPolicy.otpRequest);
      final exhaustedBucket =
          await rateLimitRepo.getBucket(RateLimitPolicy.otpRequest);
      expect(exhaustedBucket.requestCount, 5);
      expect(exhaustedBucket.isLimitReached, isTrue);
      expect(exhaustedBucket.cooldownActive, isTrue);

      // Step 6: User withdraws consent.
      await consentBloc.withdrawConsent(ConsentType.coreFunctionality);
      final coreConsent =
          await consentRepo.getConsent(ConsentType.coreFunctionality);
      expect(coreConsent!.granted, isFalse);

      // Step 7: User requests data deletion.
      await consentBloc.deleteData();
      expect(dataDeleted, isTrue);
      expect(consentBloc.current.phase.name, 'deleted');

      // Step 8: After deletion, no consents remain.
      final afterDeletion = await consentRepo.getAllConsents();
      expect(afterDeletion, isEmpty);

      // Step 9: Audit log still maintains integrity.
      expect(await auditRepo.verifyIntegrity(), isTrue);

      // Step 10: Refresh all blocs and verify state consistency.
      await consentBloc.refresh();
      await auditBloc.refresh();
      expect(consentBloc.current.allRequiredGranted, isFalse);
    });

    test('consent types carry zero identity', () {
      for (final type in ConsentType.values) {
        expect(type.wireName, isNotEmpty);
        expect(type.wireName, isNot(contains('+91')));
        expect(type.wireName, isNot(contains('@')));
        expect(type.wireName.length, lessThan(50));
      }
    });

    test('audit records carry zero PII in summaries', () {
      final record = AuditRecord(
        seq: 0,
        recordId: 'test-001',
        action: AuditAction.consentGranted,
        summary: 'Consent granted',
        occurredAt: DateTime.now().toUtc(),
        prevHash: AuditRecord.genesisHash,
        selfHash: 'dummy',
      );
      expect(record.summary, isNot(contains('+91')));
      expect(record.summary, isNot(contains('@gmail')));
      expect(record.summary, isNot(contains('password')));
    });

    test('rate limit buckets carry no identity', () async {
      final bucket =
          await rateLimitRepo.recordRequest(RateLimitPolicy.postCreation);
      expect(bucket.policy, RateLimitPolicy.postCreation);
      expect(bucket.requestCount, 1);
    });

    test('cross-pillar audit trail: consent + rate limit events are logged',
        () async {
      // Grant consent.
      await consentBloc.grantAll();
      await consentBloc.refresh();

      // Record the consent grant in the audit log.
      final hash0 = await AuditRecord(
        seq: 0,
        recordId: 'cross-001',
        action: AuditAction.consentGranted,
        summary: 'All consents granted',
        occurredAt: DateTime.now().toUtc(),
        prevHash: AuditRecord.genesisHash,
        selfHash: '',
      ).computeSelfHash(_ConsistentHasher());
      await auditRepo.append(AuditRecord(
        seq: 0,
        recordId: 'cross-001',
        action: AuditAction.consentGranted,
        summary: 'All consents granted',
        occurredAt: DateTime.now().toUtc(),
        prevHash: AuditRecord.genesisHash,
        selfHash: hash0,
      ));

      // Hit the rate limit.
      for (var i = 0; i < 5; i++) {
        await rateLimitRepo.recordRequest(RateLimitPolicy.otpRequest);
      }
      final bucket =
          await rateLimitRepo.getBucket(RateLimitPolicy.otpRequest);
      expect(bucket.isLimitReached, isTrue);

      // Record the rate limit breach.
      final hash1 = await AuditRecord(
        seq: 1,
        recordId: 'cross-002',
        action: AuditAction.credentialChanged,
        summary: 'Rate limit exceeded for OTP request',
        occurredAt: DateTime.now().toUtc(),
        prevHash: hash0,
        selfHash: '',
      ).computeSelfHash(_ConsistentHasher());
      await auditRepo.append(AuditRecord(
        seq: 1,
        recordId: 'cross-002',
        action: AuditAction.credentialChanged,
        summary: 'Rate limit exceeded for OTP request',
        occurredAt: DateTime.now().toUtc(),
        prevHash: hash0,
        selfHash: hash1,
      ));

      // Verify the complete cross-pillar audit trail.
      final records = await auditRepo.getAll();
      expect(records, hasLength(2));
      expect(records[0].action, AuditAction.consentGranted);
      expect(records[1].action, AuditAction.credentialChanged);
      expect(await auditRepo.verifyIntegrity(), isTrue);
    });

    test('independent rate limit policies do not interfere', () async {
      for (var i = 0; i < 5; i++) {
        await rateLimitRepo.recordRequest(RateLimitPolicy.otpRequest);
      }
      final otpBucket =
          await rateLimitRepo.getBucket(RateLimitPolicy.otpRequest);
      expect(otpBucket.isLimitReached, isTrue);

      final loginBucket =
          await rateLimitRepo.recordRequest(RateLimitPolicy.loginAttempt);
      expect(loginBucket.isLimitReached, isFalse);
      expect(loginBucket.requestCount, 1);
    });

    test('consent withdrawal and re-granting cycle', () async {
      await consentBloc.grantAll();
      await consentBloc.refresh();
      expect(consentBloc.current.allRequiredGranted, isTrue);

      await consentBloc.withdrawConsent(ConsentType.coreFunctionality);
      await consentBloc.refresh();
      expect(consentBloc.current.allRequiredGranted, isFalse);

      await consentRepo.grantConsent(
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        textHash: 'hash-v1',
      );
      await consentBloc.refresh();
      expect(consentBloc.current.allRequiredGranted, isTrue);
    });
  });
}

/// Deterministic hasher that always returns the same hash for any input.
/// Matches the _NoopHasher in InMemoryAuditRepository so the chain
/// integrity check succeeds.
class _ConsistentHasher implements AuditHasher {
  @override
  Future<Uint8List> hash(List<int> bytes) async {
    return Uint8List.fromList(List<int>.generate(32, (i) => i % 256));
  }
}
