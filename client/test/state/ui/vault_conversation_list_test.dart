import 'dart:async';

import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/domain/conversation_bloc.dart';
import 'package:civic_commons/state/domain/conversation_state.dart';
import 'package:civic_commons/state/domain/peer_handle.dart';
import 'package:civic_commons/state/domain/pending_request_summary.dart';
import 'package:civic_commons/state/ui/vault_conversation_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [SecureFlagService] fake recording enable calls (mirrors the
/// same fake used by the SecureScreenWrapper tests).
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

/// Scripted [ConversationBloc] fake (mirrors the interface only).
class _FakeConversationBloc implements ConversationBloc {
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

Widget _wrap(ConversationBloc bloc,
        {List<PendingRequestSummary> requests = const [],
        ValueChanged<String>? onAccept,
        SecureFlagService? secureFlagService}) =>
    MaterialApp(
      home: VaultConversationListScreen(
        bloc: bloc,
        contextMeta: '@peer_local',
        onNewConversation: () {},
        onConversationTap: (_) {},
        pendingRequests: requests,
        onAcceptRequest: onAccept,
        secureFlagService: secureFlagService,
      ),
    );

const _hashA =
    'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';

/// Double-pump: broadcast streams deliver on a microtask after emission.
Future<void> _pumpEmit(WidgetTester tester, _FakeConversationBloc bloc,
    ConversationState state) async {
  bloc.emit(state);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('VaultConversationListScreen - rendering (Task 6.1)', () {
    testWidgets('shows a loader until the bloc emits', (tester) async {
      final bloc = _FakeConversationBloc();
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('THE VAULT'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('renders conversation tiles with E2EE ciphertext previews',
        (tester) async {
      final bloc = _FakeConversationBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(
          tester,
          bloc,
          const ConversationState(
            conversations: [
              ConversationSummary(id: 'c1', participantHash: _hashA),
            ],
            hasLoaded: true,
          ));

      // The peer handle is the derived non-PII form.
      expect(find.text(formatPeerHandle(_hashA)), findsOneWidget);
      // The preview is ALWAYS the fixed E2EE label — never a plaintext
      // snippet (shoulder-surfing protection, DESIGN §6.2).
      expect(find.text('Preview: [end-to-end encrypted]'), findsOneWidget);
      // The full blind hash is never rendered.
      expect(find.textContaining(_hashA), findsNothing);
      await bloc.close();
    });

    testWidgets('renders the empty state when there are no conversations',
        (tester) async {
      final bloc = _FakeConversationBloc();
      await tester.pumpWidget(_wrap(bloc));
      await _pumpEmit(tester, bloc,
          const ConversationState(hasLoaded: true, conversations: []));

      expect(find.text('No conversations yet'), findsOneWidget);
      await bloc.close();
    });
  });

  group('VaultConversationListScreen - pending requests (Task 6.1)', () {
    testWidgets('renders the request queue with count and accept buttons',
        (tester) async {
      final bloc = _FakeConversationBloc();
      await tester.pumpWidget(_wrap(
        bloc,
        requests: [
          const PendingRequestSummary(id: 'r1', requesterHash: _hashA),
          const PendingRequestSummary(
              id: 'r2',
              requesterHash:
                  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        ],
        onAccept: (_) {},
      ));
      await _pumpEmit(tester, bloc,
          const ConversationState(hasLoaded: true, conversations: []));

      expect(find.text('PENDING REQUESTS (2)'), findsOneWidget);
      expect(find.text(formatPeerHandle(_hashA)), findsOneWidget);
      expect(find.text('wants to connect'), findsNWidgets(2));
      expect(find.text('Accept'), findsNWidgets(2));
      await bloc.close();
    });

    testWidgets('accept invokes the callback with the request id',
        (tester) async {
      final bloc = _FakeConversationBloc();
      String? accepted;
      await tester.pumpWidget(_wrap(
        bloc,
        requests: [
          const PendingRequestSummary(id: 'r1', requesterHash: _hashA)
        ],
        onAccept: (id) => accepted = id,
      ));
      await _pumpEmit(tester, bloc,
          const ConversationState(hasLoaded: true, conversations: []));

      await tester.tap(find.text('Accept'));
      await tester.pump();

      expect(accepted, 'r1');
      await bloc.close();
    });

    testWidgets(
        'request section renders READ-ONLY when no accept handler is '
        'wired (inbox never invisible)', (tester) async {
      final bloc = _FakeConversationBloc();
      await tester.pumpWidget(MaterialApp(
        home: VaultConversationListScreen(
          bloc: bloc,
          onNewConversation: () {},
          onConversationTap: (_) {},
          pendingRequests: const [
            PendingRequestSummary(id: 'r1', requesterHash: _hashA),
          ],
        ),
      ));
      await _pumpEmit(tester, bloc,
          const ConversationState(hasLoaded: true, conversations: []));

      // The queue is still visible (count + handle) — just without buttons.
      expect(find.text('PENDING REQUESTS (1)'), findsOneWidget);
      expect(find.text(formatPeerHandle(_hashA)), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      await bloc.close();
    });

    testWidgets(
        'late subscribe: renders the CURRENT state when the bloc was '
        'started before subscription', (tester) async {
      final bloc = _FakeConversationBloc();
      // Emit BEFORE the widget mounts (broadcast stream, no replay): the
      // screen must pull the current state via refresh() on init.
      bloc.emit(const ConversationState(
        hasLoaded: true,
        conversations: [
          ConversationSummary(id: 'c1', participantHash: _hashA),
        ],
      ));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      await tester.pump();

      expect(find.text(formatPeerHandle(_hashA)), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await bloc.close();
    });
  });

  group('VaultConversationListScreen - navigation (Task 6.1)', () {
    testWidgets('tapping a conversation invokes onConversationTap with its id',
        (tester) async {
      final bloc = _FakeConversationBloc();
      String? opened;
      await tester.pumpWidget(MaterialApp(
        home: VaultConversationListScreen(
          bloc: bloc,
          onNewConversation: () {},
          onConversationTap: (id) => opened = id,
        ),
      ));
      await _pumpEmit(
          tester,
          bloc,
          const ConversationState(
            conversations: [
              ConversationSummary(id: 'c1', participantHash: _hashA),
            ],
            hasLoaded: true,
          ));

      await tester.tap(find.text(formatPeerHandle(_hashA)));
      await tester.pump();

      expect(opened, 'c1');
      await bloc.close();
    });

    testWidgets('FAB invokes onNewConversation', (tester) async {
      final bloc = _FakeConversationBloc();
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: VaultConversationListScreen(
          bloc: bloc,
          onNewConversation: () => tapped = true,
        ),
      ));
      await _pumpEmit(tester, bloc,
          const ConversationState(hasLoaded: true, conversations: []));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      expect(tapped, isTrue);
      await bloc.close();
    });
  });

  group('VaultConversationListScreen - FLAG_SECURE (Task 6.1)', () {
    testWidgets('enables FLAG_SECURE on mount', (tester) async {
      final flag = FakeSecureFlagService();
      final bloc = _FakeConversationBloc();
      await tester.pumpWidget(_wrap(bloc, secureFlagService: flag));
      await tester.pump();

      expect(flag.enableCalls, 1);
      await bloc.close();
    });
  });
}
