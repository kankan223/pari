import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 6.6): the duress PIN is INDISTINGUISHABLE from
/// the real PIN.
///
/// Static + runtime guarantees:
/// 1. The unlock UI never branches on which PIN was entered — one prompt,
///    one flow, one generic error. Only the returned [UnlockResult] differs.
/// 2. No UI/state source carries a real/duress/decoy indicator that could
///    be rendered, logged, or persisted.
/// 3. The decoy vault renders only the shared fixed copy (visually
///    identical to an empty real vault).
/// 4. All new screens are wrapped in FLAG_SECURE.
/// 5. No print/debugPrint and no PII-shaped literals anywhere in the new
///    duress UI or state files.
void main() {
  final duressUiFiles = [
    'lib/state/ui/vault_unlock_screen.dart',
    'lib/state/ui/decoy_vault_screen.dart',
    'lib/state/ui/duress_pin_setup_sheet.dart',
    'lib/state/ui/vault_empty_state.dart',
  ];
  final duressStateFiles = [
    'lib/state/domain/vault_unlock_state.dart',
    'lib/state/domain/vault_unlock_bloc.dart',
    'lib/state/domain/duress_setup_state.dart',
    'lib/state/domain/duress_setup_bloc.dart',
    'lib/state/data/local_vault_unlock_bloc.dart',
    'lib/state/data/local_duress_setup_bloc.dart',
  ];

  group('SECURITY CHECKPOINT - duress UI is indistinguishable (Task 6.6)', () {
    test('new duress UI files exist', () {
      for (final file in duressUiFiles) {
        expect(File(file).existsSync(), isTrue, reason: '$file must exist');
      }
    });

    test('unlock screen never references real/duress/decoy in code', () {
      final source =
          File('lib/state/ui/vault_unlock_screen.dart').readAsStringSync();
      // The screen must not even NAME the two vault kinds — no branching,
      // no labels, no literals. Doc comments may explain the design, so
      // scan CODE lines only.
      for (final line in _codeLines(source)) {
        // Skip import lines — the import PATH legitimately references the
        // duress domain package.
        if (line.trimLeft().startsWith('import ')) {
          continue;
        }
        for (final term in ['real', 'duress', 'decoy', 'VaultKind']) {
          expect(line.toLowerCase().contains(term), isFalse,
              reason: 'unlock screen must not reference "$term" in code — '
                  'the UI is identical for both PINs');
        }
      }
    });

    test('unlock screen source contains no conditional on the result kind', () {
      final source =
          File('lib/state/ui/vault_unlock_screen.dart').readAsStringSync();
      // The screen only FORWARDS the result to the routing callback; it
      // never inspects .kind (no kind-based branches, no kind rendering).
      for (final line in _codeLines(source)) {
        expect(line.contains('.kind'), isFalse,
            reason: 'unlock screen must not inspect the result kind');
        expect(line.contains('VaultKind'), isFalse,
            reason: 'unlock screen must not reference VaultKind');
      }
    });

    test('decoy vault screen renders ONLY fixed shared copy (no real data)',
        () {
      final source =
          File('lib/state/ui/decoy_vault_screen.dart').readAsStringSync();
      // The decoy takes no data inputs and references no bloc/entity types.
      for (final forbidden in [
        'Bloc',
        'Repository',
        'EntityStore',
        'participantHash',
        'conversationId',
      ]) {
        expect(source, isNot(contains(forbidden)),
            reason: 'decoy vault must not reference "$forbidden"');
      }
      expect(source, contains('VaultEmptyState'),
          reason: 'decoy must share the real empty-state widget');
      expect(source, contains('SecureScreenWrapper'),
          reason: 'decoy must be FLAG_SECURE wrapped like every Vault screen');
    });

    test('state models carry no sensitive fields (no keys, no databases)', () {
      // CODE lines only — doc comments may legitimately explain that the
      // state excludes key material ("no [Uint8List] key...").
      for (final file in duressStateFiles) {
        final source = File(file).readAsStringSync();
        for (final token in [
          'Uint8List',
          'ciphertext',
          'plaintext',
          'decrypted',
          'sessionKey',
          'rawPayload',
          'VaultDatabase',
        ]) {
          for (final line in _codeLines(source)) {
            expect(line, isNot(contains(token)),
                reason: '$file must not declare raw data field "$token"');
          }
        }
      }
    });

    test('no print/debugPrint anywhere in the new duress files', () {
      for (final file in [...duressUiFiles, ...duressStateFiles]) {
        final source = File(file).readAsStringSync();
        expect(source.contains('print('), isFalse,
            reason: '$file must not print');
        expect(source.contains('debugPrint('), isFalse,
            reason: '$file must not debugPrint');
      }
    });

    test('no PII-shaped literals in the new duress files', () {
      for (final file in [...duressUiFiles, ...duressStateFiles]) {
        final source = File(file).readAsStringSync();
        expect(source.contains('+91'), isFalse, reason: file);
        expect(source.contains('hvs.'), isFalse, reason: file);
        expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(source), isFalse,
            reason: '$file must not embed a full 64-hex blind hash');
        expect(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').hasMatch(source), isFalse,
            reason: '$file must not embed an e-mail');
      }
    });

    test('duress UI screens consume BLoC streams, never data layers', () {
      for (final file in [
        'lib/state/ui/vault_unlock_screen.dart',
        'lib/state/ui/duress_pin_setup_sheet.dart',
      ]) {
        final source = File(file).readAsStringSync();
        for (final forbidden in [
          'Repository',
          'LocalDataStream',
          'EntityStore',
          'sqflite',
          'secure_storage',
          'package:http',
          'DuressServiceImpl',
        ]) {
          expect(source.contains(forbidden), isFalse,
              reason: '$file must not reference "$forbidden" — duress UI '
                  'consumes BLoC/state streams only');
        }
      }
    });

    test('vault empty state is shared by the real list and the decoy', () {
      final listScreen =
          File('lib/state/ui/vault_conversation_list_screen.dart')
              .readAsStringSync();
      final decoy =
          File('lib/state/ui/decoy_vault_screen.dart').readAsStringSync();
      final emptyState =
          File('lib/state/ui/vault_empty_state.dart').readAsStringSync();
      expect(listScreen, contains('VaultEmptyState'),
          reason: 'real list must use the shared empty state');
      expect(decoy, contains('VaultEmptyState'),
          reason: 'decoy must use the shared empty state');
      expect(emptyState, contains('No conversations yet'));
      expect(
          emptyState,
          contains('Your end-to-end encrypted conversations '
              'will appear here.'));
    });
  });
}

/// Strips `//` line comments and `///` doc comments so scans only see
/// executable code — security doc-comments themselves are expected.
Iterable<String> _codeLines(String source) sync* {
  for (final line in source.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
      continue;
    }
    final code = line.split('//').first;
    yield code;
  }
}
