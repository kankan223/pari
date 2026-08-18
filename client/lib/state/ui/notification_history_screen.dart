import 'package:flutter/material.dart';

import '../../notification/domain/notification_record.dart';
import '../../notification/domain/notification_type.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_state.dart';
import 'ledger_theme.dart';

/// The notification history screen (Task 10.4 — Notification System).
///
/// Renders the full list of notifications (newest first) with unread badge
/// counts, per-type filter chips, and mark-as-read interactions. Each
/// notification shows its fixed type icon, public-label title/body, and
/// relative timestamp.
///
/// SECURITY CHECKPOINT (10.4): the screen renders ONLY the public-label
/// title/body text, fixed type labels, integer counts, and timestamps.
/// No blind hash, no phone number, no identity, no token ever appears
/// in the widget tree. Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class NotificationHistoryScreen extends StatefulWidget {
  /// The notification BLoC (injected — never constructed here).
  final NotificationBloc bloc;

  /// Injectable FLAG_SECURE service (test seam).
  final SecureFlagService? secureFlagService;

  const NotificationHistoryScreen({
    super.key,
    required this.bloc,
    this.secureFlagService,
  });

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  NotificationState? _last;
  NotificationType? _filter;

  @override
  void initState() {
    super.initState();
    _last = widget.bloc.current;
    widget.bloc.state.listen((state) {
      if (!mounted) return;
      setState(() => _last = state);
    });
    widget.bloc.refresh();
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final state = _last ?? const NotificationState();
    final filtered =
        _filter == null ? state.notifications : state.forType(_filter!);

    return _secure(Scaffold(
      backgroundColor: LedgerTheme.paper,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: LedgerTheme.ink,
        foregroundColor: Colors.white,
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () => widget.bloc.markAllRead(),
              child: const Text(
                'Mark all read',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // --- Type filter chips ---
          _buildFilterChips(state),
          // --- Notification list ---
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : _buildNotificationList(filtered),
          ),
        ],
      ),
    ));
  }

  Widget _buildFilterChips(NotificationState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: LedgerTheme.paper,
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            selected: _filter == null,
            onTap: () => setState(() => _filter = null),
          ),
          const SizedBox(width: 8),
          ...NotificationType.values.map((type) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: type.label,
                  selected: _filter == type,
                  onTap: state.isTypeEnabled(type)
                      ? () => setState(() => _filter = type)
                      : null,
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildNotificationList(List records) {
    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        return _NotificationTile(
          record: record,
          onTap: () => widget.bloc.markRead(record.id),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: LedgerTheme.ink.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications',
            style: TextStyle(
              fontSize: 16,
              color: LedgerTheme.ink.withAlpha(120),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single notification tile.
class _NotificationTile extends StatelessWidget {
  final NotificationRecord record;
  final VoidCallback onTap;

  const _NotificationTile({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _typeIcon(record.type),
      title: Text(
        record.title,
        style: TextStyle(
          fontWeight: record.isRead ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: Text(record.body),
      trailing: record.isRead
          ? null
          : Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: LedgerTheme.verifiedEmerald,
                shape: BoxShape.circle,
              ),
            ),
      onTap: onTap,
    );
  }

  Widget _typeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.karmaEvent:
        return const Icon(Icons.star, color: LedgerTheme.civicGold);
      case NotificationType.caseAssignment:
        return const Icon(Icons.shield, color: LedgerTheme.verifiedEmerald);
      case NotificationType.ledgerReviewRequest:
        return const Icon(Icons.rate_review, color: LedgerTheme.ink);
    }
  }
}

/// A filter chip used in the type filter bar.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? LedgerTheme.verifiedEmerald : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? LedgerTheme.verifiedEmerald
                : LedgerTheme.ink.withAlpha(60),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : LedgerTheme.ink,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
