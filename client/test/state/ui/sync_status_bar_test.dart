import 'dart:async';

import 'package:civic_commons/state/domain/sync_status.dart';
import 'package:civic_commons/state/domain/sync_status_bloc.dart';
import 'package:civic_commons/state/ui/sync_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted [SyncStatusBloc] fake for widget tests — emits states the test
/// pushes. Mirrors the interface only (clean architecture: the widget talks
/// to the BLoC interface, never a concrete data layer).
///
/// [refresh] re-emits the last pushed state (like the real bloc re-derives on
/// refresh), so late-subscribe behavior can be tested.
class FakeSyncStatusBloc implements SyncStatusBloc {
  final StreamController<SyncStatusState> _controller =
      StreamController<SyncStatusState>.broadcast();
  SyncStatusState? _last;

  @override
  Stream<SyncStatusState> get state => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> refresh() async {
    final last = _last;
    // Yield one microtask like the real bloc (its refresh awaits network +
    // queue reads before emitting), so the StreamBuilder is subscribed by the
    // time the state lands. (Future.value — NOT Future.delayed: a delayed
    // zero-duration future schedules a Timer, which the test framework flags.)
    await Future<void>.value();
    if (last != null) {
      _controller.add(last);
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void emit(SyncStatusState state) {
    _last = state;
    _controller.add(state);
  }
}

Widget _wrap(SyncStatusBloc bloc) => MaterialApp(
      home: Scaffold(body: SyncStatusBar(bloc: bloc)),
    );

SyncStatusState _state(SyncStatus status,
        {int pending = 0, bool syncing = false, DateTime? lastSyncAt}) =>
    SyncStatusState(
      status: status,
      pendingCount: pending,
      isSyncing: syncing,
      lastSyncAt: lastSyncAt,
    );

/// Emits a state and pumps TWICE. The widget's StreamBuilder receives
/// broadcast-stream events on a microtask, so a single pump can render before
/// the delivery lands (verified empirically — the first emission works, later
/// ones need a second pump). Two pumps make every emission deterministic.
Future<void> _pumpEmit(
  WidgetTester tester,
  FakeSyncStatusBloc bloc,
  SyncStatusState state,
) async {
  bloc.emit(state);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('SyncStatusBar - renders all four states (Task 5.4)', () {
    testWidgets('LIVE shows the green LIVE chip with no badge', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.live));

      expect(find.text('LIVE'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('CACHED shows the amber CACHED chip', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.cached));

      expect(find.text('CACHED'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_queue_rounded), findsOneWidget);
    });

    testWidgets('QUEUED shows the blue QUEUED chip', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.queued));

      expect(find.text('QUEUED'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload_rounded), findsOneWidget);
    });

    testWidgets('OFFLINE shows the grey OFFLINE chip', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.offline));

      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('renders nothing before the bloc emits', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('LIVE'), findsNothing);
      expect(find.byType(SyncStatusBar), findsOneWidget);
    });

    testWidgets(
        'renders the CURRENT status when the bloc was started before '
        'subscription (late subscribe)', (tester) async {
      // Simulate main() → start() → build: the emission happens before the
      // widget's StreamBuilder subscribes (broadcast stream, no replay). The
      // bar must call refresh() on init to pull the current state.
      final bloc = FakeSyncStatusBloc();
      bloc.emit(_state(SyncStatus.queued, pending: 3));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      await tester.pump();

      expect(find.text('QUEUED'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('SyncStatusBar - pending-count badge (Task 5.4)', () {
    testWidgets('badge shows the pending count when > 0', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.queued, pending: 3));

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('badge updates when the count changes', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.queued, pending: 1));
      expect(find.text('1'), findsOneWidget);

      await _pumpEmit(tester, bloc, _state(SyncStatus.queued, pending: 5));
      expect(find.text('5'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('badge disappears when the queue drains', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.queued, pending: 2));
      expect(find.text('2'), findsOneWidget);

      await _pumpEmit(tester, bloc, _state(SyncStatus.live, pending: 0));
      expect(find.text('2'), findsNothing);
    });
  });

  group('SyncStatusBar - LIVE <-> OFFLINE transitions (Task 5.4)', () {
    testWidgets('follows state transitions from the bloc stream',
        (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.live));
      expect(find.text('LIVE'), findsOneWidget);

      // Network drop.
      await _pumpEmit(tester, bloc, _state(SyncStatus.offline));
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);

      // Reconnection.
      await _pumpEmit(tester, bloc, _state(SyncStatus.queued, pending: 2));
      expect(find.text('QUEUED'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // Queue drained -> live.
      await _pumpEmit(tester, bloc, _state(SyncStatus.live));
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });
  });

  group('SyncStatusBar - subtle sync progress indicator (Task 5.4)', () {
    testWidgets('shows a progress indicator while syncing', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(
          tester, bloc, _state(SyncStatus.queued, pending: 2, syncing: true));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('hides the indicator once the sync run finishes',
        (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(
          tester, bloc, _state(SyncStatus.queued, pending: 2, syncing: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _pumpEmit(tester, bloc, _state(SyncStatus.live, syncing: false));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('no indicator when idle (even with a badge)', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.queued, pending: 4));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('4'), findsOneWidget);
    });
  });

  group('SyncStatusBar - tap-to-expand (Task 5.4)', () {
    testWidgets('tap reveals last-sync timestamp and queue count',
        (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      final syncedAt = DateTime.now().subtract(const Duration(minutes: 5));
      await _pumpEmit(tester, bloc,
          _state(SyncStatus.queued, pending: 3, lastSyncAt: syncedAt));

      expect(find.textContaining('Last synced:'), findsNothing);

      await tester.tap(find.byType(SyncStatusBar));
      await tester.pump();

      expect(find.textContaining('Last synced:'), findsOneWidget);
      expect(find.textContaining('5m ago'), findsOneWidget);
      expect(find.textContaining('3 pending mutations'), findsOneWidget);
    });

    testWidgets('tapping again collapses the panel', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(
          tester, bloc, _state(SyncStatus.live, lastSyncAt: DateTime.now()));

      await tester.tap(find.byType(SyncStatusBar));
      await tester.pump();
      expect(find.textContaining('Last synced:'), findsOneWidget);

      await tester.tap(find.byType(SyncStatusBar));
      await tester.pump();
      expect(find.textContaining('Last synced:'), findsNothing);
    });

    testWidgets('single pending mutation uses singular wording',
        (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc,
          _state(SyncStatus.queued, pending: 1, lastSyncAt: DateTime.now()));
      await tester.tap(find.byType(SyncStatusBar));
      await tester.pump();

      expect(find.textContaining('1 pending mutation'), findsOneWidget);
    });

    testWidgets('never-synced device shows "Never"', (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.live));
      await tester.tap(find.byType(SyncStatusBar));
      await tester.pump();

      expect(find.textContaining('Last synced: Never'), findsOneWidget);
    });
  });

  group('formatLastSync - pure formatting (Task 5.4)', () {
    final now = DateTime.utc(2026, 8, 5, 12, 0, 0);

    test('null means never synced', () {
      expect(formatLastSync(null, now: now), 'Never');
    });

    test('under a minute is "Just now"', () {
      expect(
        formatLastSync(now.subtract(const Duration(seconds: 30)), now: now),
        'Just now',
      );
    });

    test('minutes, hours, and days render relatively', () {
      expect(
        formatLastSync(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago',
      );
      expect(
        formatLastSync(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        formatLastSync(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
    });

    test('older than a week falls back to a compact date', () {
      final old = DateTime.utc(2026, 7, 20, 8, 30);
      expect(formatLastSync(old, now: now), '20/7/2026');
    });
  });

  group('SECURITY CHECKPOINT - status bar exposes no sensitive data (Task 5.4)',
      () {
    testWidgets('widget tree contains no payload/phone/hash-shaped text',
        (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc,
          _state(SyncStatus.queued, pending: 7, lastSyncAt: DateTime.now()));
      await tester.tap(find.byType(SyncStatusBar));
      await tester.pump();

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(texts, isNot(contains('+91')));
      expect(texts, isNot(contains('@')));
      expect(texts, isNot(contains('hvs.')));
      // No 64-hex blind-hash-shaped strings.
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      // No JWT-shaped segments.
      expect(
        RegExp(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')
            .hasMatch(texts),
        isFalse,
      );
    });

    testWidgets('tooltip/labels are fixed enum strings, not user data',
        (tester) async {
      final bloc = FakeSyncStatusBloc();
      await tester.pumpWidget(_wrap(bloc));

      await _pumpEmit(tester, bloc, _state(SyncStatus.queued, pending: 12));
      await tester.tap(find.byType(SyncStatusBar));
      await tester.pump();

      // Only the fixed enum label, the non-sensitive count badge (pure
      // digits), and fixed informational strings may appear — nothing derived
      // from payloads, hashes, or identities can be rendered.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      for (final t in texts) {
        final isCountBadge = RegExp(r'^\d+$').hasMatch(t);
        expect(
            t.startsWith('QUEUED') ||
                t.startsWith('Last synced:') ||
                t.startsWith('12 pending') ||
                isCountBadge,
            isTrue,
            reason: 'unexpected text rendered: $t');
      }
    });
  });
}
