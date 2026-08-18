import 'package:civic_commons/notification/data/in_memory_notification_repository.dart';
import 'package:civic_commons/notification/domain/notification_preferences.dart';
import 'package:civic_commons/notification/domain/notification_record.dart';
import 'package:civic_commons/notification/domain/notification_repository.dart';
import 'package:civic_commons/notification/domain/notification_type.dart';
import 'package:civic_commons/state/data/local_notification_bloc.dart';
import 'package:civic_commons/state/domain/notification_state.dart';
import 'package:flutter_test/flutter_test.dart';

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
          body: 'Verified.',
          createdAt: DateTime.utc(2026, 8, 18, 10),
        ),
        NotificationRecord(
          id: 'notif-002',
          type: NotificationType.caseAssignment,
          title: 'Case assigned',
          body: 'CC-0047.',
          createdAt: DateTime.utc(2026, 8, 18, 9),
        ),
      ],
    );
    bloc = LocalNotificationBloc(repository: repo);
  });

  tearDown(() async {
    await bloc.close();
  });

  test('initial state is idle', () {
    expect(bloc.current.phase, NotificationPhase.idle);
  });

  test('refresh transitions to ready with notifications', () async {
    await bloc.refresh();
    expect(bloc.current.phase, NotificationPhase.ready);
    expect(bloc.current.notifications.length, 2);
    expect(bloc.current.unreadCount, 2);
  });

  test('markRead marks a notification as read', () async {
    await bloc.refresh();
    expect(bloc.current.unreadCount, 2);

    await bloc.markRead('notif-001');
    expect(bloc.current.unreadCount, 1);
  });

  test('markAllRead marks all as read', () async {
    await bloc.refresh();
    await bloc.markAllRead();
    expect(bloc.current.unreadCount, 0);
  });

  test('savePreferences updates preferences', () async {
    await bloc.refresh();
    expect(bloc.current.isTypeEnabled(NotificationType.karmaEvent), true);

    await bloc.savePreferences(
      bloc.current.preferences.withType(NotificationType.karmaEvent, false),
    );
    expect(bloc.current.isTypeEnabled(NotificationType.karmaEvent), false);
  });

  test('repository failure maps to error state', () async {
    final failingBloc = LocalNotificationBloc(
      repository: _FailingNotificationRepo(),
    );
    await failingBloc.refresh();
    expect(failingBloc.current.phase, NotificationPhase.error);
    await failingBloc.close();
  });

  test('state stream emits updates', () async {
    final states = <NotificationState>[];
    final sub = bloc.state.listen(states.add);

    await bloc.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(states.length, 2); // loading + ready
    expect(states[0].phase, NotificationPhase.loading);
    expect(states[1].phase, NotificationPhase.ready);

    await sub.cancel();
  });
}

/// A notification repository that always fails.
class _FailingNotificationRepo implements NotificationRepository {
  @override
  Future<List<NotificationRecord>> getAll() async =>
      throw Exception('db down');

  @override
  Future<List<NotificationRecord>> getByType(NotificationType type) async =>
      throw Exception('db down');

  @override
  Future<int> getUnreadCount() async => throw Exception('db down');

  @override
  Future<void> markRead(String id) async => throw Exception('db down');

  @override
  Future<void> markAllRead() async => throw Exception('db down');

  @override
  Future<void> insert(NotificationRecord record) async =>
      throw Exception('db down');

  @override
  Future<NotificationPreferences> getPreferences() async =>
      throw Exception('db down');

  @override
  Future<void> savePreferences(NotificationPreferences prefs) async =>
      throw Exception('db down');
}
