import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/war_room/domain/evidence_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 16, 12);
  final sealedFile = Uint8List.fromList(List.generate(64, (i) => i + 1));
  final dekEnvelope = Uint8List.fromList(List.generate(48, (i) => i + 200));

  EvidenceEnvelope envelope({String caseNumber = 'CC-0047'}) =>
      EvidenceEnvelope(
        evidenceId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        caseNumber: caseNumber,
        sizeBytes: 2048,
        mimeType: 'image/jpeg',
        createdAt: t0,
        sealedFile: sealedFile,
        dekEnvelope: dekEnvelope,
      );

  group('EvidenceEnvelope codec (Task 8.2)', () {
    test('round-trips through the wire frame byte-identically', () {
      final frame = encodeEvidenceEnvelope(envelope());
      final decoded = decodeEvidenceEnvelope(frame);
      expect(decoded.evidenceId, envelope().evidenceId);
      expect(decoded.caseNumber, 'CC-0047');
      expect(decoded.sizeBytes, 2048);
      expect(decoded.mimeType, 'image/jpeg');
      expect(decoded.createdAt, t0);
      expect(decoded.sealedFile, sealedFile);
      expect(decoded.dekEnvelope, dekEnvelope);
    });

    test('wire frame carries ZERO identity fields', () {
      final json = jsonDecode(utf8.decode(encodeEvidenceEnvelope(envelope())))
          as Map<String, Object?>;
      expect(json.keys, isNot(contains('file_name')));
      expect(json.keys, isNot(contains('filename')));
      expect(json.keys, isNot(contains('path')));
      expect(json.keys, isNot(contains('phone')));
      expect(json.keys, isNot(contains('hash')));
      expect(json.keys, isNot(contains('name')));
      expect(json.keys, isNot(contains('exif')));
      // The ONLY user-derived bytes are the sealed file + wrapped DEK.
      expect(json.keys, contains('sealed_file'));
      expect(json.keys, contains('dek_envelope'));
    });

    test('rejects unsupported versions', () {
      final bad = jsonEncode({'v': 2, 'evidence_id': 'x'});
      expect(
        () => decodeEvidenceEnvelope(Uint8List.fromList(utf8.encode(bad))),
        throwsFormatException,
      );
    });

    test('rejects non-object / malformed payloads', () {
      expect(
        () => decodeEvidenceEnvelope(Uint8List.fromList(utf8.encode('[1]'))),
        throwsFormatException,
      );
      final bad = jsonEncode({
        'v': 1,
        'evidence_id': 'x',
        'case_number': 'CC-1',
        'size_bytes': -5, // negative size must be rejected
        'mime_type': 'image/jpeg',
        'created_at': 0,
        'sealed_file': 'AAAA',
        'dek_envelope': 'AAAA',
      });
      expect(
        () => decodeEvidenceEnvelope(Uint8List.fromList(utf8.encode(bad))),
        throwsFormatException,
      );
    });

    test('rejects invalid base64 fields', () {
      final bad = jsonEncode({
        'v': 1,
        'evidence_id': 'x',
        'case_number': 'CC-1',
        'size_bytes': 10,
        'mime_type': 'image/jpeg',
        'created_at': 0,
        'sealed_file': '!!!not-base64!!!',
        'dek_envelope': 'AAAA',
      });
      expect(
        () => decodeEvidenceEnvelope(Uint8List.fromList(utf8.encode(bad))),
        throwsFormatException,
      );
    });
  });

  group('DekEnvelope binary codec (Task 8.2)', () {
    test('round-trips fields byte-identically', () {
      final e = DekEnvelope(
        algorithm: DekEnvelope.alg,
        wrappedDek: Uint8List.fromList(List.generate(44, (i) => i + 3)),
        recipientFingerprint: '1a2b3c4d5e6f7a8b',
      );
      final decoded = DekEnvelope.fromBytes(e.toBytes());
      expect(decoded.algorithm, DekEnvelope.alg);
      expect(decoded.wrappedDek, e.wrappedDek);
      expect(decoded.recipientFingerprint, e.recipientFingerprint);
    });

    test('rejects unsupported version and trailing bytes', () {
      final e = DekEnvelope(
        algorithm: DekEnvelope.alg,
        wrappedDek: Uint8List.fromList(List.generate(44, (i) => i + 3)),
        recipientFingerprint: '1a2b3c4d',
      );
      final bytes = e.toBytes();
      bytes[0] = 9; // version byte
      expect(() => DekEnvelope.fromBytes(bytes), throwsFormatException);
      bytes[0] = 1;
      final trailing = Uint8List.fromList([...bytes, 0]);
      expect(() => DekEnvelope.fromBytes(trailing), throwsFormatException);
    });
  });
}
