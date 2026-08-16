import 'dart:typed_data';

import 'package:civic_commons/war_room/data/hmac_report_signer.dart';
import 'package:civic_commons/war_room/data/in_memory_custody_log.dart';
import 'package:civic_commons/war_room/domain/custody_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic SHA-256 hasher for the append-only chain tests.
///
/// Input-derived (no internal counter), so `buildEvent` and
/// `verifyIntegrity` recompute the SAME digest for the same canonical bytes
/// — exactly like the real SHA-256, but without the crypto dependency.
class _FixedHasher implements Sha256Hasher {
  @override
  Future<Uint8List> hash(List<int> bytes) async => Uint8List.fromList(
      List.generate(32, (i) => (bytes.length + i * 7) & 0xff));
}

void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);

  group('InMemoryCustodyLog (Task 8.6)', () {
    test('buildEvent chains: seq 0 uses the zero prevHash, links follow',
        () async {
      final log = InMemoryCustodyLog();

      final first = await log.buildEvent(
        caseNumber: 'CC-0047',
        type: CustodyEventType.caseFiled,
        actor: 'VICTIM',
        at: t0,
      );
      expect(first.seq, 0);
      expect(first.prevHash, InMemoryCustodyLog.zeroHash);
      expect(first.selfHash, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(first.selfHash), isTrue);
      await log.append(first);

      final second = await log.buildEvent(
        caseNumber: 'CC-0047',
        type: CustodyEventType.autoTriage,
        actor: 'SYSTEM',
        at: t0.add(const Duration(minutes: 1)),
      );
      expect(second.seq, 1);
      expect(second.prevHash, first.selfHash,
          reason: 'the second event must link to the first selfHash');
    });

    test('append enforces the chain invariants (seq + prevHash) or throws',
        () async {
      final log = InMemoryCustodyLog();
      final first = await log.buildEvent(
        caseNumber: 'CC-0047',
        type: CustodyEventType.caseFiled,
        actor: 'VICTIM',
        at: t0,
      );
      await log.append(first);

      // Wrong sequence → rejected.
      final badSeq = CustodyEvent(
        seq: 5,
        caseNumber: 'CC-0047',
        type: CustodyEventType.analystAssigned,
        actor: 'AN-0001',
        at: t0,
        prevHash: first.selfHash,
        selfHash: 'x' * 64,
      );
      expect(() => log.append(badSeq), throwsStateError);

      // Correct seq but broken prevHash link → rejected.
      final badLink = CustodyEvent(
        seq: 1,
        caseNumber: 'CC-0047',
        type: CustodyEventType.analystAssigned,
        actor: 'AN-0001',
        at: t0,
        prevHash: 'f' * 64,
        selfHash: 'x' * 64,
      );
      expect(() => log.append(badLink), throwsStateError);

      // A correctly linked event succeeds.
      final second = await log.buildEvent(
        caseNumber: 'CC-0047',
        type: CustodyEventType.analystAssigned,
        actor: 'AN-0001',
        at: t0,
      );
      await log.append(second);
      expect(await log.entries('CC-0047'), hasLength(2));
    });

    test('verifyIntegrity recomputes every hash — tampering is detected',
        () async {
      final log = InMemoryCustodyLog(hasher: _FixedHasher());
      for (var i = 0; i < 3; i++) {
        await log.append(await log.buildEvent(
          caseNumber: 'CC-0047',
          type: CustodyEventType.values[i],
          actor: i == 0 ? 'VICTIM' : 'AN-0001',
          at: t0.add(Duration(minutes: i)),
        ));
      }
      expect(await log.verifyIntegrity(), isTrue);

      // Out-of-band tamper: swap an event's actor (e.g. an attacker editing
      // who filed the case). The recomputation breaks the chain.
      final chain = await log.entries('CC-0047');
      final forged = CustodyEvent(
        seq: 0,
        caseNumber: chain[0].caseNumber,
        type: chain[0].type,
        actor: 'IMPOSTOR', // edited actor — the stored selfHash no longer fits
        at: chain[0].at,
        prevHash: chain[0].prevHash,
        selfHash: chain[0].selfHash,
      );
      log.tamperForTest('CC-0047', 0, forged);
      expect(await log.verifyIntegrity(), isFalse,
          reason: 'an edited actor must break the hash chain');
    });

    test('verifyIntegrity detects a reordered chain (mid-chain swap)',
        () async {
      final log = InMemoryCustodyLog();
      await log.append(await log.buildEvent(
        caseNumber: 'CC-0048',
        type: CustodyEventType.caseFiled,
        actor: 'VICTIM',
        at: t0,
      ));
      await log.append(await log.buildEvent(
        caseNumber: 'CC-0048',
        type: CustodyEventType.caseWithdrawn,
        actor: 'VICTIM',
        at: t0.add(const Duration(minutes: 5)),
      ));
      final chain = await log.entries('CC-0048');
      // Swap the two events so seq 1 (WITHDRAWN) sits at index 0 — a
      // deliberately reordered chain.
      log.tamperForTest('CC-0048', 0, chain[1]);
      log.tamperForTest('CC-0048', 1, chain[0]);
      expect(await log.verifyIntegrity(), isFalse,
          reason: 'a reordered chain must fail verification');
    });

    test('append-only contract: events accumulate, never mutate', () async {
      final log = InMemoryCustodyLog(hasher: _FixedHasher());
      final first = await log.buildEvent(
        caseNumber: 'CC-0047',
        type: CustodyEventType.caseFiled,
        actor: 'VICTIM',
        at: t0,
      );
      await log.append(first);
      final second = await log.buildEvent(
        caseNumber: 'CC-0047',
        type: CustodyEventType.autoTriage,
        actor: 'SYSTEM',
        at: t0,
      );
      await log.append(second);

      final chain = await log.entries('CC-0047');
      expect(chain, hasLength(2));
      expect(chain[0].selfHash, first.selfHash,
          reason: 'appending must not rewrite earlier events');
      expect(chain[1].prevHash, first.selfHash);
    });

    test('lastEvent returns the tail; null for an empty chain', () async {
      final log = InMemoryCustodyLog();
      expect(await log.lastEvent('CC-0000'), isNull);
      final first = await log.buildEvent(
        caseNumber: 'CC-0047',
        type: CustodyEventType.caseFiled,
        actor: 'VICTIM',
        at: t0,
      );
      await log.append(first);
      final last = await log.lastEvent('CC-0047');
      expect(last!.selfHash, first.selfHash);
    });
  });

  group('HmacReportSigner (Task 8.6)', () {
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final report = VerifiedIntelReport(
      caseNumber: 'CC-0047',
      severityLabel: 'HIGH',
      slaHours: 48,
      analystCount: 2,
      filedAt: DateTime.utc(2026, 8, 10, 12),
      stageLine: 'Drafting report',
    );

    test('sign is deterministic — the same report yields the same signature',
        () async {
      final signer = HmacReportSigner(key: key);
      final a = await signer.sign(report);
      final b = await signer.sign(report);
      expect(a.signature, b.signature);
      expect(a.signature, isNotEmpty);
    });

    test('verify accepts the genuine signature, rejects tampered reports',
        () async {
      final signer = HmacReportSigner(key: key);
      final signed = await signer.sign(report);
      expect(await signer.verify(signed), isTrue);

      // Tampered severity label → verification fails.
      final tampered = SignedReport(
        report: VerifiedIntelReport(
          caseNumber: report.caseNumber,
          severityLabel: 'LOW', // edited
          slaHours: report.slaHours,
          analystCount: report.analystCount,
          filedAt: report.filedAt,
          stageLine: report.stageLine,
        ),
        signature: signed.signature,
        signedAt: signed.signedAt,
      );
      expect(await signer.verify(tampered), isFalse);
    });

    test('a different key fails verification', () async {
      final signerA = HmacReportSigner(key: key);
      final signerB = HmacReportSigner(
          key: Uint8List.fromList(List.generate(32, (i) => i + 9)));
      final signed = await signerA.sign(report);
      expect(await signerB.verify(signed), isFalse);
    });

    test('canonicalText is deterministic and non-PII', () async {
      final text = report.canonicalText();
      expect(text, contains('VERIFIED INTEL REPORT'));
      expect(text, contains('CASE #CC-0047'));
      expect(text, contains('(blinded)'));
      expect(text.contains(RegExp(r'\+?[0-9]{10,}')), isFalse,
          reason: 'no phone-shaped string in the signed text');
    });
  });

  group('LegalAidHandoffEnvelope (Task 8.6)', () {
    final handoff = LegalAidHandoff(
      id: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
      caseNumber: 'CC-0047',
      reportSignature: 'abcDEF123_-',
      analystId: 'AN-0003',
      queuedAt: DateTime.utc(2026, 8, 10, 12, 30),
    );

    test('encode/decode round-trips the strict frame', () {
      final envelope = LegalAidHandoffEnvelope.fromHandoff(handoff);
      final decoded = LegalAidHandoffEnvelope.decode(envelope.encode());
      expect(decoded.id, handoff.id);
      expect(decoded.caseNumber, handoff.caseNumber);
      expect(decoded.reportSignature, handoff.reportSignature);
      expect(decoded.analystId, handoff.analystId);
      expect(decoded.queuedAt, handoff.queuedAt.toUtc());
    });

    test('frame carries ZERO identity fields', () {
      final encoded = LegalAidHandoffEnvelope.fromHandoff(handoff).encode();
      for (final forbidden in ['phone', 'email', 'name', 'victim', 'body']) {
        expect(encoded.toLowerCase(), isNot(contains(forbidden)),
            reason: '$forbidden must never appear in the frame');
      }
    });

    test('decode rejects wrong version', () {
      final encoded = LegalAidHandoffEnvelope.fromHandoff(handoff).encode();
      final bad = encoded.replaceFirst('"v":1', '"v":2');
      expect(() => LegalAidHandoffEnvelope.decode(bad),
          throwsA(isA<FormatException>()));
    });

    test('decode rejects malformed JSON and missing fields', () {
      expect(() => LegalAidHandoffEnvelope.decode('not json'),
          throwsA(isA<FormatException>()));
      expect(() => LegalAidHandoffEnvelope.decode('[]'),
          throwsA(isA<FormatException>()));
      final missing = LegalAidHandoffEnvelope.fromHandoff(handoff)
          .encode()
          .replaceFirst(',"case_number":"CC-0047"', '');
      expect(() => LegalAidHandoffEnvelope.decode(missing),
          throwsA(isA<FormatException>()));
    });
  });
}
