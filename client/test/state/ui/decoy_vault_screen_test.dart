import 'dart:async';
import 'dart:io';

import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/domain/conversation_bloc.dart';
import 'package:civic_commons/state/domain/conversation_state.dart';
import 'package:civic_commons/state/ui/decoy_vault_screen.dart';
import 'package:civic_commons/state/ui/vault_conversation_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 6.6): [DecoyVaultScreen] is visually INDISTINGUISHABLE
/// from the real vault conversation list when it is empty — same masthead,
/// same header, same empty-state copy — renders no real data of any kind,
/// and enables FLAG_SECURE on mount.
void main() {
  group('DecoyVaultScreen - rendering', () {
    testWidgets('renders masthead + CONVERSATIONS + the shared empty state',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DecoyVaultScreen()));
      await tester.pump();

      expect(find.text('THE VAULT'), findsOneWidget);
      expect(find.text('CONVERSATIONS'), findsOneWidget);
      expect(find.text('No conversations yet'), findsOneWidget);
      expect(
          find.text('Your end-to-end encrypted conversations will appear '
              'here.'),
          findsOneWidget);
    });

    testWidgets('is textually IDENTICAL to the real empty vault list',
        (tester) async {
      // Real vault with zero conversations (bloc emits an empty state).
      final realBloc = _EmptyConversationBloc();
      await tester.pumpWidget(MaterialApp(
        home: VaultConversationListScreen(bloc: realBloc),
      ));
      await realBloc.start();
      await tester.pump();
      await tester.pump();
      final realTexts = _visibleTexts(tester);

      // Decoy vault.
      await tester.pumpWidget(const MaterialApp(home: DecoyVaultScreen()));
      await tester.pump();
      final decoyTexts = _visibleTexts(tester);

      expect(decoyTexts, realTexts,
          reason: 'a duress-unlocked decoy must look exactly like a real '
              'empty vault');
      expect(decoyTexts, contains('No conversations yet'));

      await realBloc.close();
    });

    testWidgets('renders NO data content — no rows, no previews, no handles',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: DecoyVaultScreen()));
      await tester.pump();

      // No ListTile rows, no peer handles, no conversation ids.
      expect(find.byType(ListTile), findsNothing);
      expect(find.textContaining('@peer_'), findsNothing);
      final texts = _visibleTexts(tester);
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      expect(texts, isNot(contains('Preview:')));
    });
  });

  group('DecoyVaultScreen - FLAG_SECURE + static scans (Task 6.6)', () {
    testWidgets('enables FLAG_SECURE on mount', (tester) async {
      final flag = _RecordingFlagService();
      await tester.pumpWidget(MaterialApp(
        home: DecoyVaultScreen(secureFlagService: flag),
      ));
      await tester.pump();

      expect(flag.enableCalls, 1,
          reason: 'mounting the decoy vault must enable FLAG_SECURE — it '
              'must not be distinguishable by its security guard either');
    });

    test('source wraps in SecureScreenWrapper and takes no data inputs', () {
      final source =
          File('lib/state/ui/decoy_vault_screen.dart').readAsStringSync();
      expect(source, contains('SecureScreenWrapper'));
      // No bloc/repository/entity types may be referenced — there is
      // nothing real to leak.
      for (final forbidden in ['Bloc', 'Repository', 'EntityStore']) {
        expect(source, isNot(contains(forbidden)),
            reason: 'decoy vault must not reference "$forbidden"');
      }
      expect(source.contains('print('), isFalse);
      expect(source.contains('debugPrint('), isFalse);
    });
  });
}

String _visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join('|');

class _RecordingFlagService implements SecureFlagService {
  int enableCalls = 0;

  @override
  Future<void> disableSecureFlag() async {}

  @override
  Future<void> enableSecureFlag() async {
    enableCalls++;
  }

  @override
  Future<bool> isSecureFlagSupported() async => true;
}

/// Emits one loaded EMPTY conversation state (mirrors the real screen's
/// freshly-registered state).
class _EmptyConversationBloc implements ConversationBloc {
  final StreamController<ConversationState> _controller =
      StreamController<ConversationState>.broadcast();

  @override
  Stream<ConversationState> get state => _controller.stream;

  @override
  Future<void> start() async {
    await refresh();
  }

  @override
  Future<void> refresh() async {
    _controller.add(const ConversationState(hasLoaded: true));
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}
