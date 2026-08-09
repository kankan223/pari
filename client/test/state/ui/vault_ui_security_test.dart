import 'dart:async';
import 'dart:io';

import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/domain/conversation_bloc.dart';
import 'package:civic_commons/state/domain/conversation_state.dart';
import 'package:civic_commons/state/domain/message_bloc.dart';
import 'package:civic_commons/state/domain/message_state.dart';
import 'package:civic_commons/state/ui/vault_conversation_detail_screen.dart';
import 'package:civic_commons/state/ui/vault_conversation_list_screen.dart';
import 'package:civic_commons/state/ui/vault_masthead.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 6.1): the Vault UI is a pure presentation
/// layer. Every screen:
/// 1. is wrapped in [SecureScreenWrapper] (FLAG_SECURE — no screenshots),
/// 2. consumes BLoC state streams only (no repository/database/network),
/// 3. renders peers exclusively through [formatPeerHandle] (non-PII handles),
/// 4. never renders plaintext — message previews and bubbles are fixed
///    "[end-to-end encrypted]" labels.
/// No PII may appear in the widget tree, in fixed labels, or in logs.
void main() {
  final vaultUiFiles = _dartFilesUnder('lib/state/ui')
    ..removeWhere((p) => p.endsWith('vault_theme.dart'));

  group('SECURITY CHECKPOINT - Vault UI is BLoC-only (Task 6.1)', () {
    test('vault UI files exist', () {
      for (final name in [
        'vault_masthead.dart',
        'vault_conversation_list_screen.dart',
        'vault_conversation_detail_screen.dart',
        'message_bubble.dart',
        'vault_pending_requests_section.dart',
      ]) {
        expect(
          vaultUiFiles.any((p) => p.endsWith(name)),
          isTrue,
          reason: '$name must exist under lib/state/ui',
        );
      }
    });

    test('screens consume BLoC streams, never data layers', () {
      for (final file in vaultUiFiles) {
        final source = File(file).readAsStringSync();
        for (final forbidden in [
          'Repository',
          'LocalDataStream',
          'EntityStore',
          'QueuePayloadCipher',
          'sqflite',
          'hive_ce',
          'secure_storage',
          'package:http',
          'SyncSink',
          'NetworkInfoProvider',
        ]) {
          expect(source.contains(forbidden), isFalse,
              reason: '$file must not reference "$forbidden" — Vault UI '
                  'consumes BLoC/state streams only');
        }
      }
    });

    test('no prints / debugPrint anywhere in the Vault UI', () {
      for (final file in vaultUiFiles) {
        final source = File(file).readAsStringSync();
        expect(source.contains('print('), isFalse,
            reason: '$file must not print');
        expect(source.contains('debugPrint('), isFalse,
            reason: '$file must not debugPrint');
      }
    });

    test('no raw PII-shaped literals in any Vault UI source', () {
      for (final file in vaultUiFiles) {
        final source = File(file).readAsStringSync();
        expect(source.contains('+91'), isFalse, reason: file);
        expect(source.contains('hvs.'), isFalse, reason: file);
        expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(source), isFalse,
            reason: '$file must not embed a full 64-hex blind hash');
        expect(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').hasMatch(source), isFalse,
            reason: '$file must not embed an e-mail');
      }
    });

    test('peers are rendered only via formatPeerHandle', () {
      final files = [
        for (final f in vaultUiFiles)
          if (f.endsWith('vault_conversation_list_screen.dart') ||
              f.endsWith('vault_conversation_detail_screen.dart') ||
              f.endsWith('vault_pending_requests_section.dart'))
            f,
      ];
      for (final file in files) {
        final source = File(file).readAsStringSync();
        expect(source, contains('formatPeerHandle'),
            reason: '$file must render peers through formatPeerHandle');
      }
    });
  });

  group('SECURITY CHECKPOINT - FLAG_SECURE on all Vault screens (Task 6.1)',
      () {
    test('every Vault screen source wraps in SecureScreenWrapper', () {
      for (final screen in [
        'vault_conversation_list_screen.dart',
        'vault_conversation_detail_screen.dart',
      ]) {
        final file = vaultUiFiles.firstWhere((p) => p.endsWith(screen));
        final source = File(file).readAsStringSync();
        expect(source, contains('SecureScreenWrapper'),
            reason: '$screen must be wrapped in SecureScreenWrapper '
                '(FLAG_SECURE anti-screenshot guard)');
      }
    });

    testWidgets('the list screen enables FLAG_SECURE on mount (runtime)',
        (tester) async {
      final flag = _RecordingFlagService();
      final bloc = _EmptyConversationBloc();
      await tester.pumpWidget(MaterialApp(
        home: VaultConversationListScreen(
          bloc: bloc,
          secureFlagService: flag,
        ),
      ));
      await tester.pump();

      expect(flag.enableCalls, 1,
          reason: 'mounting the Vault conversation list must enable '
              'FLAG_SECURE');
      await bloc.close();
    });

    testWidgets('the detail screen enables FLAG_SECURE on mount (runtime)',
        (tester) async {
      final flag = _RecordingFlagService();
      final bloc = _EmptyMessageBloc();
      await tester.pumpWidget(MaterialApp(
        home: VaultConversationDetailScreen(
          bloc: bloc,
          participantHash:
              'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2',
          secureFlagService: flag,
        ),
      ));
      await tester.pump();

      expect(flag.enableCalls, 1,
          reason: 'mounting the Vault conversation detail must enable '
              'FLAG_SECURE');
      await bloc.close();
    });
  });

  group('SECURITY CHECKPOINT - runtime widget tree leaks nothing (Task 6.1)',
      () {
    testWidgets('the list screen renders no PII-shaped text', (tester) async {
      final bloc = _EmptyConversationBloc();
      await tester.pumpWidget(MaterialApp(
        home: VaultConversationListScreen(
          bloc: bloc,
          contextMeta:
              '@peer_a1b2c3', // must already be a PII-free display handle
        ),
      ));
      bloc.emit(const ConversationState(
        hasLoaded: true,
        conversations: [
          ConversationSummary(
            id: 'c1',
            participantHash:
                'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2',
          ),
        ],
      ));
      await tester.pump();
      await tester.pump();

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(texts, isNot(contains('+91')));
      expect(texts, isNot(contains('hvs.')));
      // Display handles are the derived, non-PII form (@peer_xxxxxx).
      expect(texts, contains('@peer_a1b2c3'));
      // No full 64-hex blind hash anywhere in the tree.
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      expect(
          RegExp(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')
              .hasMatch(texts),
          isFalse);
      await bloc.close();
    });

    testWidgets('the detail screen renders no PII-shaped text', (tester) async {
      final bloc = _EmptyMessageBloc();
      await tester.pumpWidget(MaterialApp(
        home: VaultConversationDetailScreen(
          bloc: bloc,
          participantHash:
              '9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8',
        ),
      ));
      bloc.emit(const MessageState(
        conversationId: 'c1',
        hasLoaded: true,
        messages: [MessageSummary(id: 'm1')],
      ));
      await tester.pump();
      await tester.pump();

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(texts, isNot(contains('+91')));
      expect(texts, isNot(contains('hvs.')));
      // No full 64-hex blind hash anywhere in the tree.
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      // Message ids / conversation ids never surface. (The peer handle
      // '@peer_9a8b7c' is the derived display form — the raw 64-hex hash is
      // already excluded by the regex above.)
      expect(texts, isNot(contains('m1')));
      expect(texts, isNot(contains('c1')));
      expect(
          texts,
          isNot(contains(
              '9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8')));
      await bloc.close();
    });

    testWidgets('the masthead alone renders no PII-shaped text',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: VaultMasthead(contextMeta: '@peer_a1b2c3')),
      ));
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      expect(texts, isNot(contains('+91')));
      expect(texts, isNot(contains('hvs.')));
    });
  });
}

// --- fakes ----------------------------------------------------------------

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

class _EmptyConversationBloc implements ConversationBloc {
  final StreamController<ConversationState> _controller =
      StreamController<ConversationState>.broadcast();
  ConversationState? _last;

  @override
  Stream<ConversationState> get state => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> refresh() async {
    final last = _last;
    await Future<void>.value();
    if (last != null) {
      _controller.add(last);
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void emit(ConversationState state) {
    _last = state;
    _controller.add(state);
  }
}

class _EmptyMessageBloc implements MessageBloc {
  final StreamController<MessageState> _controller =
      StreamController<MessageState>.broadcast();
  MessageState? _last;

  @override
  Stream<MessageState> get state => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> refresh() async {
    final last = _last;
    await Future<void>.value();
    if (last != null) {
      _controller.add(last);
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void emit(MessageState state) {
    _last = state;
    _controller.add(state);
  }
}

List<String> _dartFilesUnder(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) {
    return [];
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .toList();
}
