import 'dart:async';

import 'package:civic_commons/repository/domain/message.dart';
import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/domain/message_bloc.dart';
import 'package:civic_commons/state/domain/message_side.dart';
import 'package:civic_commons/state/domain/message_state.dart';
import 'package:civic_commons/state/domain/peer_handle.dart';
import 'package:civic_commons/state/ui/vault_conversation_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [SecureFlagService] fake recording enable calls.
class FakeSecureFlagService implements SecureFlagService {
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

/// Scripted [MessageBloc] fake (mirrors the interface only).
class _FakeMessageBloc implements MessageBloc {
  final StreamController<MessageState> _controller =
      StreamController<MessageState>.broadcast();
  MessageState? _last;
  final List<String> sent = [];

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
  Future<void> send(String text) async {
    sent.add(text);
  }

  @override
  void setPeerTyping(bool isTyping) {}

  @override
  void setLastReadMsgId(String? msgId) {}

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void emit(MessageState state) {
    _last = state;
    _controller.add(state);
  }
}

MessageSummary _msg(String id,
        {bool delivered = false,
        MessageDirection direction = MessageDirection.received,
        String? content,
        DateTime? expiresAt}) =>
    MessageSummary(
      id: id,
      direction: direction,
      delivered: delivered,
      content: content,
      expiresAt: expiresAt,
    );

const _hashA =
    'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';

Widget _wrap(MessageBloc bloc,
        {MessageSideResolver? sideResolver,
        VoidCallback? onBack,
        SecureFlagService? secureFlagService}) =>
    MaterialApp(
      home: VaultConversationDetailScreen(
        bloc: bloc,
        participantHash: _hashA,
        onBack: onBack,
        sideResolver: sideResolver ?? defaultMessageSide,
        secureFlagService: secureFlagService,
      ),
    );

Future<void> _pumpEmit(
    WidgetTester tester, _FakeMessageBloc bloc, MessageState state) async {
  bloc.emit(state);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('VaultConversationDetailScreen - header (Task 6.1)', () {
    testWidgets('renders the derived peer handle and the E2EE lock',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          const MessageState(
            conversationId: 'c1',
            hasLoaded: true,
          ));

      expect(find.text(formatPeerHandle(_hashA)), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      // The full blind hash is never rendered.
      expect(find.textContaining(_hashA), findsNothing);
      await bloc.close();
    });

    testWidgets('back button invokes onBack', (tester) async {
      final bloc = _FakeMessageBloc();
      var back = false;
      await tester.pumpWidget(_wrap(bloc, onBack: () => back = true));

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(back, isTrue);
      await bloc.close();
    });

    testWidgets('shows a loader until the bloc emits', (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await bloc.close();
    });

    testWidgets('renders the empty thread state', (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(tester, bloc,
          const MessageState(conversationId: 'c1', hasLoaded: true));

      expect(find.text('No messages yet'), findsOneWidget);
      await bloc.close();
    });

    testWidgets(
        'late subscribe: renders the CURRENT thread when the bloc '
        'was started before subscription', (tester) async {
      final bloc = _FakeMessageBloc();
      // Emit BEFORE the widget mounts (broadcast stream, no replay): the
      // screen must pull the current state via refresh() on init.
      bloc.emit(MessageState(
        conversationId: 'c1',
        hasLoaded: true,
        messages: [MessageSummary(id: 'm1', delivered: false)],
      ));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      await tester.pump();

      expect(find.text('[end-to-end encrypted]'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await bloc.close();
    });
  });

  group('MessageBubble - sent/received styling (Task 6.1)', () {
    testWidgets('received bubble is left-aligned with the E2EE placeholder',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          MessageState(
            conversationId: 'c1',
            hasLoaded: true,
            messages: [_msg('m1', delivered: true)],
          ));

      expect(find.text('[end-to-end encrypted]'), findsOneWidget);
      final align = tester.widget<Align>(find.byType(Align).first);
      expect(align.alignment, Alignment.centerLeft);
      await bloc.close();
    });

    testWidgets('sent bubble is right-aligned with Vault Blue background',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          MessageState(
            conversationId: 'c1',
            hasLoaded: true,
            messages: [
              _msg('m1', direction: MessageDirection.sent),
            ],
          ));

      final align = tester.widget<Align>(find.byType(Align).first);
      expect(align.alignment, Alignment.centerRight);
      final container = tester.widget<Container>(find
          .ancestor(
              of: find.text('[end-to-end encrypted]'),
              matching: find.byType(Container))
          .first);
      expect((container.decoration as BoxDecoration?)?.color,
          const Color(0xFF1A3D6B));
      await bloc.close();
    });

    testWidgets('renders the queued indicator for an undelivered sent message',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          MessageState(
            conversationId: 'c1',
            hasLoaded: true,
            messages: [
              _msg('m1', direction: MessageDirection.sent),
            ],
          ));

      expect(find.text('Sending when online'), findsOneWidget);
      expect(find.text('✓'), findsOneWidget);
      expect(find.text('sent'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('a sent + delivered message renders the ✓✓ receipt',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          MessageState(
            conversationId: 'c1',
            hasLoaded: true,
            messages: [
              _msg('m1', direction: MessageDirection.sent, delivered: true),
            ],
          ));

      // Direction is authoritative (Task 6.3): a SENT acked message shows
      // the delivered receipt — the old delivered-heuristic is superseded.
      expect(find.text('✓✓'), findsOneWidget);
      expect(find.text('delivered'), findsOneWidget);
      expect(find.text('Sending when online'), findsNothing);
      await bloc.close();
    });

    testWidgets('an explicit resolver renders the acked message as sent',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(
        bloc,
        sideResolver: (_) => MessageSide.sent,
      ));
      await _pumpEmit(
          tester,
          bloc,
          MessageState(
            conversationId: 'c1',
            hasLoaded: true,
            messages: [_msg('m1', delivered: true)],
          ));

      expect(find.text('✓✓'), findsOneWidget);
      expect(find.text('delivered'), findsOneWidget);
      expect(find.text('Sending when online'), findsNothing);
      await bloc.close();
    });

    testWidgets('shows the Expires marker when the message has a TTL',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          MessageState(
            conversationId: 'c1',
            hasLoaded: true,
            messages: [
              _msg('m1',
                  direction: MessageDirection.sent,
                  expiresAt: DateTime(2026, 9, 1)),
            ],
          ));

      expect(find.text('Expires'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('never renders message ids or payload-shaped text',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          MessageState(
            conversationId: 'c1',
            hasLoaded: true,
            messages: [_msg('m1'), _msg('m2', delivered: true)],
          ));

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(texts, isNot(contains('m1')));
      expect(texts, isNot(contains('m2')));
      expect(texts, isNot(contains('c1')));
      expect(texts, isNot(contains(_hashA)));
      await bloc.close();
    });
  });

  group('VaultConversationDetailScreen - FLAG_SECURE (Task 6.1)', () {
    testWidgets('enables FLAG_SECURE on mount', (tester) async {
      final flag = FakeSecureFlagService();
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc, secureFlagService: flag));
      await tester.pump();

      expect(flag.enableCalls, 1);
      await bloc.close();
    });
  });

  group('MessageBubble - decrypted content (Task 6.3)', () {
    testWidgets('renders decrypted content instead of the placeholder',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          MessageState(
            conversationId: 'c1',
            hasLoaded: true,
            messages: [
              _msg('m1',
                  direction: MessageDirection.sent,
                  content: 'Hello from the Vault'),
            ],
          ));

      expect(find.text('Hello from the Vault'), findsOneWidget);
      expect(find.text('[end-to-end encrypted]'), findsNothing);
      await bloc.close();
    });

    testWidgets('received content renders left with the Vault Blue bar',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          MessageState(
            conversationId: 'c1',
            hasLoaded: true,
            messages: [
              _msg('m1', content: 'Incoming plaintext'),
            ],
          ));

      final align = tester.widget<Align>(find.byType(Align).first);
      expect(align.alignment, Alignment.centerLeft);
      expect(find.text('Incoming plaintext'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('null content keeps the fixed placeholder (never leaks)',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          MessageState(
            conversationId: 'c1',
            hasLoaded: true,
            messages: [_msg('m1')],
          ));

      expect(find.text('[end-to-end encrypted]'), findsOneWidget);
      await bloc.close();
    });
  });

  group('VaultConversationDetailScreen - composer send (Task 6.3)', () {
    Finder sendButton() => find.ancestor(
          of: find.byIcon(Icons.send_rounded),
          matching: find.byType(IconButton),
        );

    testWidgets('typing and tapping send invokes bloc.send with the text',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(tester, bloc,
          const MessageState(conversationId: 'c1', hasLoaded: true));

      await tester.enterText(find.byType(TextField), 'Message text');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pump();

      expect(bloc.sent, ['Message text']);
      await bloc.close();
    });

    testWidgets('the composer clears its field after sending', (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(tester, bloc,
          const MessageState(conversationId: 'c1', hasLoaded: true));

      await tester.enterText(find.byType(TextField), 'Clear me');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
      await bloc.close();
    });

    testWidgets('an empty or whitespace-only composer cannot send',
        (tester) async {
      final bloc = _FakeMessageBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(tester, bloc,
          const MessageState(conversationId: 'c1', hasLoaded: true));

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      // The send button is disabled for empty input (onPressed null).
      final button = tester.widget<IconButton>(sendButton());
      expect(button.onPressed, isNull);
      expect(bloc.sent, isEmpty);
      await bloc.close();
    });
  });
}
