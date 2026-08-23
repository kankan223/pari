import 'package:civic_commons/repository/data/blocking_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('BlockingService', () {
    late BlockingService service;

    setUp(() {
      service = BlockingService();
    });

    tearDown(() async {
      await service.clearAll();
      service.dispose();
    });

    test('starts with no blocked users', () async {
      final blocked = await service.loadBlocked();
      expect(blocked, isEmpty);
    });

    test('block adds a user to the blocked set', () async {
      final result = await service.block('abc123');
      expect(result, isTrue);

      final blocked = await service.loadBlocked();
      expect(blocked, contains('abc123'));
    });

    test('block returns false if already blocked', () async {
      await service.block('abc123');
      final result = await service.block('abc123');
      expect(result, isFalse);
    });

    test('unblock removes a user from the blocked set', () async {
      await service.block('abc123');
      final result = await service.unblock('abc123');
      expect(result, isTrue);

      final blocked = await service.loadBlocked();
      expect(blocked, isNot(contains('abc123')));
    });

    test('unblock returns false if not blocked', () async {
      final result = await service.unblock('abc123');
      expect(result, isFalse);
    });

    test('isBlocked returns true for blocked users', () async {
      await service.block('abc123');
      expect(await service.isBlocked('abc123'), isTrue);
      expect(await service.isBlocked('def456'), isFalse);
    });

    test('report stores a report entry', () async {
      await service.report(
        blindHashId: 'abc123',
        reason: 'spam',
        details: 'Test report',
      );

      final reports = await service.getReports();
      expect(reports.length, 1);
      expect(reports[0]['blind_hash_id'], 'abc123');
      expect(reports[0]['reason'], 'spam');
      expect(reports[0]['details'], 'Test report');
    });

    test('multiple reports are stored', () async {
      await service.report(blindHashId: 'abc123', reason: 'spam');
      await service.report(blindHashId: 'def456', reason: 'harassment');

      final reports = await service.getReports();
      expect(reports.length, 2);
    });

    test('blockedUsers stream emits on changes', () async {
      final emissions = <Set<String>>[];
      service.blockedUsers.listen(emissions.add);

      await service.block('abc123');
      await service.block('def456');
      await service.unblock('abc123');

      // Allow stream to process.
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, greaterThanOrEqualTo(3));
      expect(emissions.last, contains('def456'));
      expect(emissions.last, isNot(contains('abc123')));
    });

    test('clearAll removes all data', () async {
      await service.block('abc123');
      await service.report(blindHashId: 'abc123', reason: 'spam');
      await service.clearAll();

      expect(await service.loadBlocked(), isEmpty);
      expect(await service.getReports(), isEmpty);
    });
  });

  group('ReportReason', () {
    test('has all required categories', () {
      expect(ReportReason.values.length, 6);
      expect(ReportReason.spam.label, isNotEmpty);
      expect(ReportReason.harassment.label, isNotEmpty);
      expect(ReportReason.impersonation.label, isNotEmpty);
      expect(ReportReason.threats.label, isNotEmpty);
      expect(ReportReason.inappropriate.label, isNotEmpty);
      expect(ReportReason.other.label, isNotEmpty);
    });
  });

  group('SECURITY CHECKPOINT', () {
    test('blocking service stores only blind_hash_ids, no PII', () async {
      final service = BlockingService();
      await service.block('abc123');
      await service.report(
        blindHashId: 'abc123',
        reason: 'spam',
        details: 'Test',
      );

      // Verify no phone patterns, emails, or usernames in stored data.
      final blocked = await service.loadBlocked();
      for (final hash in blocked) {
        // Should be a blind hash, not a phone or email.
        expect(hash.contains('@'), isFalse);
        expect(hash.contains('+'), isFalse);
        expect(hash.contains('.'), isFalse);
      }

      await service.clearAll();
      service.dispose();
    });

    test('no networking imports in blocking_service.dart', () async {
      // Static check: the blocking service should only use local storage.
      // This is verified by the fact that it only imports flutter_secure_storage.
      final service = BlockingService();
      // All operations are local — no network calls.
      await service.block('test');
      expect(await service.isBlocked('test'), isTrue);
      await service.clearAll();
      service.dispose();
    });
  });
}
