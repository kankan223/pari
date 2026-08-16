import 'dart:convert';
import 'dart:typed_data';

import 'ledger_category.dart';

/// A canonical wire frame for a new Ledger post (Task 7.4).
///
/// SECURITY CONTRACT: the frame carries ONLY public civic fields —
/// `category` (wire name), `pin_code` (coarse scope), `headline`, `body`.
/// It is sealed by the sync-queue cipher before storage, so the queue never
/// persists this plaintext. The codec is strict on DECODE (unknown category
/// wire names throw — a server can never smuggle an unexpected category).
class LedgerPostWireFrame {
  final LedgerCategory category;
  final String pinCode;
  final String headline;
  final String body;

  const LedgerPostWireFrame({
    required this.category,
    required this.pinCode,
    required this.headline,
    this.body = '',
  });

  Map<String, Object?> toJson() => {
        'v': 1,
        'category': category.wireName,
        'pin_code': pinCode,
        'headline': headline,
        'body': body,
      };

  static LedgerPostWireFrame fromJson(Map<String, Object?> json) {
    if (json['v'] != 1) {
      throw ArgumentError('Unsupported ledger post wire version: ${json['v']}');
    }
    final category = LedgerCategory.fromWireName(json['category']! as String);
    final pinCode = json['pin_code']! as String;
    final headline = json['headline']! as String;
    final body = (json['body'] as String?) ?? '';
    return LedgerPostWireFrame(
      category: category,
      pinCode: pinCode,
      headline: headline,
      body: body,
    );
  }
}

/// Serializes [LedgerPostWireFrame] to the opaque bytes queued for sync.
Uint8List encodeLedgerPostFrame(LedgerPostWireFrame frame) =>
    Uint8List.fromList(utf8.encode(jsonEncode(frame.toJson())));

/// Strictly decodes queued ledger post bytes; throws [FormatException] /
/// [ArgumentError] on malformed input or unknown categories.
LedgerPostWireFrame decodeLedgerPostFrame(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Ledger post frame must be a JSON object');
  }
  return LedgerPostWireFrame.fromJson(decoded);
}
