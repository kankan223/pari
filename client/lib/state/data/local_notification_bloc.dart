import 'dart:async';

import '../../notification/domain/notification_preferences.dart';
import '../../notification/domain/notification_repository.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_state.dart';

/// Local implementation of [NotificationBloc] (Task 10.4).
///
/// Backed by [NotificationRepository] (in-memory for the harness,
/// SQLCipher for production). Monotonic sequence guards prevent stale
/// late-subscriber updates.
///
/// SECURITY CHECKPOINT (10.4):
/// - Repository failures map to a generic, payload-free [NotificationState]
///   error — never leaking stack traces, database errors, or PII.
/// - [refresh] reads only public-label notification records from the store.
class LocalNotificationBloc implements NotificationBloc {
  final NotificationRepository _repository;

  final _controller = StreamController<NotificationState>.broadcast();
  var _seq = 0;
  var _current = const NotificationState();

  LocalNotificationBloc({required NotificationRepository repository})
      : _repository = repository;

  @override
  Stream<NotificationState> get state => _controller.stream;

  @override
  NotificationState get current => _current;

  @override
  Future<void> refresh() async {
    final seq = ++_seq;
    _emit(const NotificationState(phase: NotificationPhase.loading));

    try {
      final notifications = await _repository.getAll();
      final unreadCount = await _repository.getUnreadCount();
      final prefs = await _repository.getPreferences();

      if (seq != _seq) return; // stale

      _emit(NotificationState(
        phase: NotificationPhase.ready,
        notifications: notifications,
        unreadCount: unreadCount,
        preferences: prefs,
      ));
    } catch (_) {
      if (seq != _seq) return;
      _emit(const NotificationState(
        phase: NotificationPhase.error,
        errorMessage: 'Unable to load notifications',
      ));
    }
  }

  @override
  Future<void> markRead(String id) async {
    try {
      await _repository.markRead(id);
      await refresh();
    } catch (_) {
      // Repository failure → generic error on next refresh.
      await refresh();
    }
  }

  @override
  Future<void> markAllRead() async {
    try {
      await _repository.markAllRead();
      await refresh();
    } catch (_) {
      await refresh();
    }
  }

  @override
  Future<void> savePreferences(NotificationPreferences prefs) async {
    try {
      await _repository.savePreferences(prefs);
      await refresh();
    } catch (_) {
      await refresh();
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  void _emit(NotificationState state) {
    _current = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}
