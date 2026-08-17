import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/academy/domain/sandbox_wiki_wire_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _page = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const _module = '3f2504e0-4f89-41d3-9a0c-0305e82c3302';

void main() {
  group('SandboxRevisionWireFrame (Task 9.5 — sealed sync frame)', () {
    test('round-trips a revision frame', () {
      const frame = SandboxRevisionWireFrame(
        pageId: _page,
        moduleId: _module,
        title: 'Study notes',
        bodyMarkdown: '# Heading\n\nSome **notes**.',
        authorHandle: 'SA-1a2b',
        createdAtMs: 1755468000000,
      );

      final decoded =
          decodeSandboxRevisionFrame(encodeSandboxRevisionFrame(frame));

      expect(decoded.pageId, _page);
      expect(decoded.moduleId, _module);
      expect(decoded.title, 'Study notes');
      expect(decoded.bodyMarkdown, '# Heading\n\nSome **notes**.');
      expect(decoded.authorHandle, 'SA-1a2b');
      expect(decoded.createdAtMs, 1755468000000);
    });

    test('SECURITY: the frame carries UUID ids + public fields only', () {
      final json = jsonDecode(utf8.decode(encodeSandboxRevisionFrame(
        const SandboxRevisionWireFrame(
          pageId: _page,
          moduleId: _module,
          title: 'Study notes',
          bodyMarkdown: 'body',
          authorHandle: 'SA-1a2b',
          createdAtMs: 1,
        ),
      ))) as Map<String, Object?>;

      expect(
          json.keys,
          containsAll([
            'v',
            'page_id',
            'module_id',
            'title',
            'body',
            'author_handle',
            'created_at_ms'
          ]));
      // No identity keys can exist in the frame.
      for (final forbidden in ['phone', 'email', 'name', 'hash', 'device']) {
        expect(json.keys.where((k) => k.contains(forbidden)), isEmpty);
      }
    });

    test('rejects an unsupported version', () {
      expect(
        () => SandboxRevisionWireFrame.fromJson({
          'v': 2,
          'page_id': _page,
          'module_id': _module,
          'title': 't',
          'body': 'b',
          'author_handle': 'SA-1a2b',
          'created_at_ms': 1,
        }),
        throwsArgumentError,
      );
    });

    test('rejects non-UUID ids', () {
      expect(
        () => SandboxRevisionWireFrame.fromJson({
          'v': 1,
          'page_id': 'not-a-uuid',
          'module_id': _module,
          'title': 't',
          'body': 'b',
          'author_handle': 'SA-1a2b',
          'created_at_ms': 1,
        }),
        throwsArgumentError,
      );
      expect(
        () => SandboxRevisionWireFrame.fromJson({
          'v': 1,
          'page_id': _page,
          'module_id': 'not-a-uuid',
          'title': 't',
          'body': 'b',
          'author_handle': 'SA-1a2b',
          'created_at_ms': 1,
        }),
        throwsArgumentError,
      );
    });

    test('rejects a malformed author handle', () {
      expect(
        () => SandboxRevisionWireFrame.fromJson({
          'v': 1,
          'page_id': _page,
          'module_id': _module,
          'title': 't',
          'body': 'b',
          'author_handle': 'alice',
          'created_at_ms': 1,
        }),
        throwsArgumentError,
      );
    });

    test('rejects non-object payloads', () {
      expect(
        () => decodeSandboxRevisionFrame(
            Uint8List.fromList(utf8.encode('[1,2]'))),
        throwsFormatException,
      );
    });
  });
}
