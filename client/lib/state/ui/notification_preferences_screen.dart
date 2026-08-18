import 'package:flutter/material.dart';

import '../../notification/domain/notification_preferences.dart';
import '../../notification/domain/notification_type.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_state.dart';
import 'ledger_theme.dart';

/// The notification preferences screen (Task 10.4 — Notification System).
///
/// Renders per-[NotificationType] toggle switches and a master "all
/// notifications" toggle. Preferences are saved locally and never leave
/// the device (offline-first).
///
/// SECURITY CHECKPOINT (10.4): the screen renders only fixed type labels
/// and boolean toggle states. No blind hash, no phone number, no identity,
/// no token ever appears in the widget tree. Wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE).
class NotificationPreferencesScreen extends StatefulWidget {
  /// The notification BLoC (injected — never constructed here).
  final NotificationBloc bloc;

  /// Injectable FLAG_SECURE service (test seam).
  final SecureFlagService? secureFlagService;

  const NotificationPreferencesScreen({
    super.key,
    required this.bloc,
    this.secureFlagService,
  });

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  NotificationState? _last;

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

  void _toggleType(NotificationType type, bool enabled) {
    final prefs =
        _last?.preferences ?? const NotificationPreferences.allEnabled();
    widget.bloc.savePreferences(prefs.withType(type, enabled));
  }

  void _toggleAll(bool enabled) {
    final prefs =
        _last?.preferences ?? const NotificationPreferences.allEnabled();
    widget.bloc.savePreferences(prefs.withAll(enabled));
  }

  @override
  Widget build(BuildContext context) {
    final state = _last ?? const NotificationState();
    final prefs = state.preferences;

    return _secure(Scaffold(
      backgroundColor: LedgerTheme.paper,
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: LedgerTheme.ink,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // Master toggle
          SwitchListTile(
            title: const Text('All notifications'),
            subtitle: const Text('Enable or disable all notification types'),
            value: NotificationType.values.every((t) => prefs.isEnabled(t)),
            onChanged: _toggleAll,
            activeThumbColor: LedgerTheme.verifiedEmerald,
          ),
          const Divider(),

          // Per-type toggles
          ...NotificationType.values.map((type) => SwitchListTile(
                title: Text(_typeDescription(type)),
                subtitle: Text(type.label),
                value: prefs.isEnabled(type),
                onChanged: (enabled) => _toggleType(type, enabled),
                activeThumbColor: LedgerTheme.verifiedEmerald,
              )),

          const Divider(),

          // Privacy notice
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Notification preferences are stored locally on your device '
              'and are never transmitted. No personal information is included '
              'in notification content.',
              style: TextStyle(
                fontSize: 12,
                color: LedgerTheme.ink.withAlpha(120),
              ),
            ),
          ),
        ],
      ),
    ));
  }

  String _typeDescription(NotificationType type) {
    switch (type) {
      case NotificationType.karmaEvent:
        return 'Karma balance changes (verified posts, rejections, etc.)';
      case NotificationType.caseAssignment:
        return 'War Room case assignments';
      case NotificationType.ledgerReviewRequest:
        return 'Ledger peer review requests';
    }
  }
}
