import 'dart:convert';
import 'dart:typed_data';

import 'academy_module.dart';
import 'sandbox_wiki.dart';

/// A canonical wire frame for a submitted Sandbox revision (Task 9.5).
///
/// SECURITY CONTRACT: the frame carries ONLY the revision/page/module UUID
/// v4 ids, the public title, the community body, the `SA-####` author
/// handle and a UTC timestamp — zero identity, zero PII. It is SEALED by
/// the sync-queue cipher before storage, so the queue never persists this
/// plaintext (MASTER_PLAN §9.5 checkpoint: Sandbox edits are encrypted
/// before sync). The codec is strict on DECODE (bad UUID v4 ids, unknown
/// versions or malformed author handles throw — a corrupt/forged envelope
/// can never masquerade as a real revision).
class SandboxRevisionWireFrame {
  final String pageId;
  final String moduleId;
  final String title;
  final String bodyMarkdown;
  final String authorHandle;
  final int createdAtMs;

  const SandboxRevisionWireFrame({
    required this.pageId,
    required this.moduleId,
    required this.title,
    required this.bodyMarkdown,
    required this.authorHandle,
    required this.createdAtMs,
  });

  Map<String, Object?> toJson() => {
        'v': 1,
        'page_id': pageId,
        'module_id': moduleId,
        'title': title,
        'body': bodyMarkdown,
        'author_handle': authorHandle,
        'created_at_ms': createdAtMs,
      };

  static SandboxRevisionWireFrame fromJson(Map<String, Object?> json) {
    if (json['v'] != 1) {
      throw ArgumentError('Unsupported sandbox wire version: ${json['v']}');
    }
    final pageId = json['page_id']! as String;
    final moduleId = json['module_id']! as String;
    final authorHandle = json['author_handle']! as String;
    if (!UuidV4.isValid(pageId) || !UuidV4.isValid(moduleId)) {
      throw ArgumentError('Sandbox frame carries a non-UUID id');
    }
    if (!SandboxAuthorHandle.isValid(authorHandle)) {
      throw ArgumentError('Sandbox frame carries a malformed author handle');
    }
    return SandboxRevisionWireFrame(
      pageId: pageId,
      moduleId: moduleId,
      title: json['title']! as String,
      bodyMarkdown: json['body']! as String,
      authorHandle: authorHandle,
      createdAtMs: json['created_at_ms']! as int,
    );
  }
}

/// Serializes [SandboxRevisionWireFrame] to the opaque bytes queued for
/// sync (sealed by the queue repository before storage).
Uint8List encodeSandboxRevisionFrame(SandboxRevisionWireFrame frame) =>
    Uint8List.fromList(utf8.encode(jsonEncode(frame.toJson())));

/// Strictly decodes queued sandbox revision bytes; throws [FormatException]
/// / [ArgumentError] on malformed input or invalid ids/handles.
SandboxRevisionWireFrame decodeSandboxRevisionFrame(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Sandbox frame must be a JSON object');
  }
  return SandboxRevisionWireFrame.fromJson(decoded);
}
