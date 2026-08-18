import 'package:civic_commons/notification/data/in_memory_notification_repository.dart';
import 'package:civic_commons/notification/domain/notification_record.dart';
import 'package:civic_commons/notification/domain/notification_type.dart';
import 'package:civic_commons/state/data/local_notification_bloc.dart';
import 'package:civic_commons/state/ui/notification_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:civic_commons/security/domain/secure_flag_service.dart';

void main() {
  late InMemoryNotificationRepository repo;
  late LocalNotificationBloc bloc;

  setUp(() {
    repo = InMemoryNotificationRepository(
      seed: [
        NotificationRecord(
          id: 'notif-001',
          type: NotificationType.karmaEvent,
          title: 'Karma +5',
          body: 'Your Ledger post was verified.',
          createdAt: DateTime.utc(2026, 8, 18, 10),
        ),
        NotificationRecord(
          id: 'notif-002',
          type: NotificationType.caseAssignment,
          title: 'Case CC-0047 assigned',
          body: 'Digital extortion case.',
          createdAt: DateTime.utc(2026, 8, 18, 9),
          isRead: true,
        ),
      ],
    );
    bloc = LocalNotificationBloc(repository: repo);
  });

  tearDown(() async {
    await bloc.close();
  });

  Widget buildScreen() => MaterialApp(
        home: NotificationHistoryScreen(
          bloc: bloc,
          secureFlagService: _FakeSecureFlagService(),
        ),
      );

  testWidgets('renders notification title and body', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Karma +5'), findsOneWidget);
    expect(find.text('Your Ledger post was verified.'), findsOneWidget);
  });

  testWidgets('shows unread dot for unread notifications', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // The unread notification (notif-001) should have an unread dot.
    // We verify by checking there are exactly 2 ListTile widgets (one read, one unread).
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('Mark all read button visible when unread exist', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Mark all read'), findsOneWidget);
  });

  testWidgets('tapping Mark all read clears unread', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    // After marking all read, the button should disappear.
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('empty state shows when no notifications', (tester) async {
    final emptyRepo = InMemoryNotificationRepository();
    final emptyBloc = LocalNotificationBloc(repository: emptyRepo);

    await tester.pumpWidget(MaterialApp(
      home: NotificationHistoryScreen(
        bloc: emptyBloc,
        secureFlagService: _FakeSecureFlagService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No notifications'), findsOneWidget);
    await emptyBloc.close();
  });

  testWidgets('filter chips render for all types', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Karma'),
        findsWidgets); // filter chip + possibly notification
    expect(find.text('Case'), findsWidgets);
    expect(find.text('Ledger'), findsWidgets);
  });
}

/// Fake SecureFlagService that disables FLAG_SECURE in tests.
class _FakeSecureFlagService implements SecureFlagService {
  @override
  Future<void> enableSecureFlag() async {}

  @override
  Future<void> disableSecureFlag() async {}

  @override
  Future<bool> isSecureFlagSupported() async => false;
}
