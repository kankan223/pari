import 'package:civic_commons/state/domain/peer_handle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for [formatPeerHandle] (Task 6.1).
void main() {
  group('formatPeerHandle - non-PII display handle (Task 6.1)', () {
    test('is deterministic for the same hash', () {
      const hash =
          'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';
      expect(formatPeerHandle(hash), formatPeerHandle(hash));
    });

    test('renders @peer_ + first 6 hex chars, never the full hash', () {
      const hash =
          'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';
      final handle = formatPeerHandle(hash);
      expect(handle, '@peer_a1b2c3');
      expect(handle, isNot(contains(hash)));
      expect(handle.length, lessThan(20),
          reason: 'a handle must never carry a full 64-hex blind hash');
    });

    test('lowercases and trims the input', () {
      expect(formatPeerHandle('  A1B2C3D4E5F6  '), '@peer_a1b2c3');
    });

    test('handles short hashes without crashing (fragment = whole)', () {
      expect(formatPeerHandle('ab12'), '@peer_ab12');
    });

    test('produces different handles for different hashes', () {
      final a = formatPeerHandle(
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      final b = formatPeerHandle(
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
      expect(a, isNot(b));
    });

    test('output never contains a phone number, email, or full hash', () {
      final handle = formatPeerHandle(
          'c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1');
      expect(handle.contains('+91'), isFalse);
      expect(
          handle.contains('@') &&
              handle.contains('.') &&
              handle != '@peer_c1d2e3',
          isFalse);
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(handle), isFalse);
    });
  });
}
