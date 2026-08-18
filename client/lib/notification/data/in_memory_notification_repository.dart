import '../domain/notification_preferences.dart';
import '../domain/notification_record.dart';
import '../domain/notification_repository.dart';
import '../domain/notification_type.dart';

/// In-memory implementation of [NotificationRepository] (Task 10.4).
///
/// Used in the testing harness and unit tests. Production persistence
/// backs onto the SQLCipher-encrypted database (deferred to Phase 9
/// integration).
///
/// SECURITY CHECKPOINT (10.4): stores only [NotificationRecord] objects
/// carrying public labels — no identity, no PII, no tokens.
class InMemoryNotificationRepository implements NotificationRepository {
  final Map<String, NotificationRecord> _records = {};
  NotificationPreferences _prefs = const NotificationPreferences.allEnabled();

  /// Seeds the repository with an initial list of notifications.
  InMemoryNotificationRepository({List<NotificationRecord> seed = const []}) {
    for (final record in seed) {
      _records[record.id] = record;
    }
  }

  @override
  Future<List<NotificationRecord>> getAll() async {
    final sorted = _records.values.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  @override
  Future<List<NotificationRecord>> getByType(NotificationType type) async {
    return (await getAll())
        .where((r) => r.type == type)
        .toList(growable: false);
  }

  @override
  Future<int> getUnreadCount() async {
    return _records.values.where((r) => !r.isRead).length;
  }

  @override
  Future<void> markRead(String id) async {
    final existing = _records[id];
    if (existing != null) {
      _records[id] = existing.withRead();
    }
  }

  @override
  Future<void> markAllRead() async {
    _records.updateAll((_, r) => r.withRead());
  }

  @override
  Future<void> insert(NotificationRecord record) async {
    _records[record.id] = record;
  }

  @override
  Future<NotificationPreferences> getPreferences() async => _prefs;

  @override
  Future<void> savePreferences(NotificationPreferences prefs) async {
    _prefs = prefs;
  }
}
