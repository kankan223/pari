import 'dart:convert';
import 'dart:typed_data';

import 'ledger_vote.dart';

/// A canonical wire frame for a Ledger vote mutation (Task 7.5).
///
/// SECURITY CONTRACT: the frame carries ONLY the public post id + an
/// aggregate direction — NO identity, NO PII (the transport authenticates
/// the device server-side). It is sealed by the sync-queue cipher before
/// storage, so the queue never persists this plaintext. Decode is strict:
/// unknown directions throw.
class LedgerVoteWireFrame {
  final String postId;
  final LedgerVoteDirection direction;

  const LedgerVoteWireFrame({required this.postId, required this.direction});

  Map<String, Object?> toJson() => {
        'v': 1,
        'post_id': postId,
        'direction': direction.wireName,
      };

  static LedgerVoteWireFrame fromJson(Map<String, Object?> json) {
    if (json['v'] != 1) {
      throw ArgumentError('Unsupported ledger vote wire version: ${json['v']}');
    }
    final postId = json['post_id']! as String;
    final direction =
        LedgerVoteDirection.fromWireName(json['direction']! as String);
    return LedgerVoteWireFrame(postId: postId, direction: direction);
  }
}

/// Serializes [LedgerVoteWireFrame] to the opaque bytes queued for sync.
Uint8List encodeLedgerVoteFrame(LedgerVoteWireFrame frame) =>
    Uint8List.fromList(utf8.encode(jsonEncode(frame.toJson())));

/// Strictly decodes queued ledger vote bytes; throws [FormatException] /
/// [ArgumentError] on malformed input or unknown directions.
LedgerVoteWireFrame decodeLedgerVoteFrame(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Ledger vote frame must be a JSON object');
  }
  return LedgerVoteWireFrame.fromJson(decoded);
}
