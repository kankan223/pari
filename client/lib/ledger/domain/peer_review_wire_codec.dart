import 'dart:convert';
import 'dart:typed_data';

import 'peer_review.dart';

/// A canonical wire frame for a Peer Review decision (Task 7.6).
///
/// SECURITY CONTRACT: the frame carries ONLY the public post id + a
/// decision code — NO reviewer identity, NO PII (the transport
/// authenticates the reviewing peer server-side). It is sealed by the
/// sync-queue cipher before storage, so the queue never persists this
/// plaintext. Decode is strict: unknown decisions/versions throw.
class PeerReviewWireFrame {
  final String postId;
  final PeerReviewDecision decision;

  const PeerReviewWireFrame({required this.postId, required this.decision});

  Map<String, Object?> toJson() => {
        'v': 1,
        'post_id': postId,
        'decision': decision.wireName,
      };

  static PeerReviewWireFrame fromJson(Map<String, Object?> json) {
    if (json['v'] != 1) {
      throw ArgumentError('Unsupported peer review wire version: ${json['v']}');
    }
    final postId = json['post_id']! as String;
    final decision =
        PeerReviewDecision.fromWireName(json['decision']! as String);
    return PeerReviewWireFrame(postId: postId, decision: decision);
  }
}

/// Serializes [PeerReviewWireFrame] to the opaque bytes queued for sync.
Uint8List encodePeerReviewFrame(PeerReviewWireFrame frame) =>
    Uint8List.fromList(utf8.encode(jsonEncode(frame.toJson())));

/// Strictly decodes queued peer review bytes; throws [FormatException] /
/// [ArgumentError] on malformed input or unknown decisions.
PeerReviewWireFrame decodePeerReviewFrame(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Peer review frame must be a JSON object');
  }
  return PeerReviewWireFrame.fromJson(decoded);
}
