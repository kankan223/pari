import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/custody_log.dart';

/// HMAC-SHA256 [ReportSigner] (Task 8.6 — HMAC signing for the Verified
/// Intel Report).
///
/// The report's [VerifiedIntelReport.canonicalText] is MACed with a
/// 32-byte device-held key; the signature is base64url. [verify] recomputes
/// the MAC over the report's canonical text and compares in constant time —
/// a tampered report or a different key fails verification.
///
/// SECURITY CHECKPOINT (8.6): the signer operates ONLY on the deterministic,
/// non-PII report text — never on narrative, evidence bytes, or identity.
/// The signing key never leaves the device (injected from secure storage in
/// production wiring; tests inject a fixed key).
class HmacReportSigner implements ReportSigner {
  /// The device-held 32-byte HMAC key.
  final Uint8List _key;

  /// Clock-injectable for deterministic signedAt.
  final DateTime Function() _clock;

  HmacReportSigner({required Uint8List key, DateTime Function()? clock})
      : _key = key,
        _clock = clock ?? DateTime.now;

  static final Hmac _hmac = Hmac(Sha256());

  /// base64url (unpadded) — deterministic, safe in JSON/wire frames.
  static String _b64url(Uint8List bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  Future<Uint8List> _mac(List<int> message) async {
    final mac = await _hmac.calculateMac(
      message,
      secretKey: SecretKey(_key),
    );
    return Uint8List.fromList(mac.bytes);
  }

  @override
  Future<SignedReport> sign(VerifiedIntelReport report) async {
    final mac = await _mac(utf8.encode(report.canonicalText()));
    return SignedReport(
      report: report,
      signature: _b64url(mac),
      signedAt: _clock(),
    );
  }

  @override
  Future<bool> verify(SignedReport signed) async {
    final expected = await _mac(utf8.encode(signed.report.canonicalText()));
    final actual = base64Url.decode(
      signed.signature.padRight(
        signed.signature.length + ((4 - signed.signature.length % 4) % 4),
        '=',
      ),
    );
    // Constant-time-ish comparison (length check first is fine — lengths are
    // public; the byte loop never short-circuits on a mismatch).
    if (expected.length != actual.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected[i] ^ actual[i];
    }
    return diff == 0;
  }
}
