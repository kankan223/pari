import 'package:flutter/material.dart';

import '../../auth/auth_storage.dart';
import '../../auth/identity_api_client.dart';
import '../../notification/domain/notification_preferences.dart';
import '../../notification/domain/notification_type.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/notification_bloc.dart';
import '../domain/notification_state.dart';
import 'profile_screen.dart';
import 'vault_theme.dart';

/// General settings screen — notification preferences, theme, about, etc.
///
/// SECURITY CHECKPOINT: renders only boolean toggle states and fixed labels.
/// No blind hash, no phone number, no identity, no token ever appears.
/// Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class GeneralSettingsScreen extends StatefulWidget {
  final NotificationBloc notificationBloc;

  const GeneralSettingsScreen({
    super.key,
    required this.notificationBloc,
  });

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  NotificationState? _last;

  @override
  void initState() {
    super.initState();
    _last = widget.notificationBloc.current;
    widget.notificationBloc.state.listen((state) {
      if (!mounted) return;
      setState(() => _last = state);
    });
    widget.notificationBloc.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _last?.preferences ?? const NotificationPreferences.allEnabled();

    return SecureScreenWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF6ED),
        appBar: AppBar(
          title: const Text('Settings'),
          backgroundColor: VaultTheme.vaultBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: ListView(
          children: [
            // Profile section
            _buildSectionHeader('ACCOUNT'),
            _buildNavTile(
              icon: Icons.person_outline,
              title: 'Profile',
              subtitle: 'Edit your avatar and status',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      api: IdentityApiClient(
                        baseUrl: 'https://civic-commons-identity.onrender.com',
                      ),
                      storage: AuthStorage(),
                    ),
                  ),
                );
              },
            ),
            const Divider(indent: 16, endIndent: 16),

            // Notifications section
            _buildSectionHeader('NOTIFICATIONS'),
            _buildToggleTile(
              icon: Icons.notifications_outlined,
              title: 'Enable Notifications',
              subtitle: 'Master toggle for all notifications',
              value: NotificationType.values.every((t) => prefs.isEnabled(t)),
              onChanged: (enabled) {
                widget.notificationBloc.savePreferences(prefs.withAll(enabled));
              },
            ),
            _buildToggleTile(
              icon: Icons.star_outline,
              title: 'Karma Updates',
              subtitle: 'Get notified when your karma changes',
              value: prefs.isEnabled(NotificationType.karmaEvent),
              onChanged: (enabled) {
                widget.notificationBloc.savePreferences(
                  prefs.withType(NotificationType.karmaEvent, enabled),
                );
              },
            ),
            _buildToggleTile(
              icon: Icons.shield_outlined,
              title: 'Case Assignments',
              subtitle: 'Get notified when assigned to a War Room case',
              value: prefs.isEnabled(NotificationType.caseAssignment),
              onChanged: (enabled) {
                widget.notificationBloc.savePreferences(
                  prefs.withType(NotificationType.caseAssignment, enabled),
                );
              },
            ),
            _buildToggleTile(
              icon: Icons.rate_review_outlined,
              title: 'Review Requests',
              subtitle: 'Get notified when your Ledger posts need review',
              value: prefs.isEnabled(NotificationType.ledgerReviewRequest),
              onChanged: (enabled) {
                widget.notificationBloc.savePreferences(
                  prefs.withType(NotificationType.ledgerReviewRequest, enabled),
                );
              },
            ),
            const Divider(indent: 16, endIndent: 16),

            // Display section
            _buildSectionHeader('DISPLAY'),
            _buildNavTile(
              icon: Icons.brightness_6_outlined,
              title: 'Theme',
              subtitle: 'System default',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Theme customization coming soon')),
                );
              },
            ),
            const Divider(indent: 16, endIndent: 16),

            // Privacy & Security section
            _buildSectionHeader('PRIVACY & SECURITY'),
            _buildNavTile(
              icon: Icons.lock_outline,
              title: 'Privacy Policy',
              subtitle: 'How we protect your data',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Privacy policy coming soon')),
                );
              },
            ),
            _buildNavTile(
              icon: Icons.help_outline,
              title: 'Help & Support',
              subtitle: 'FAQ and contact information',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Help center coming soon')),
                );
              },
            ),
            const Divider(indent: 16, endIndent: 16),

            // About section
            _buildSectionHeader('ABOUT'),
            _buildInfoTile(
              icon: Icons.info_outline,
              label: 'Version',
              value: '1.0.0',
            ),
            _buildInfoTile(
              icon: Icons.code_outlined,
              label: 'Build',
              value: 'civic-commons-flutter',
            ),
            _buildInfoTile(
              icon: Icons.storage_outlined,
              label: 'Storage',
              value: 'Local (SQLCipher)',
            ),
            const SizedBox(height: 16),

            // Privacy notice
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE3DCC8)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Color(0xFF6E6A5E)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All settings are stored locally on your device. '
                      'No personal data is transmitted.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6E6A5E),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Color(0xFF6E6A5E),
        ),
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: const Color(0xFF1F4D3A)),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: VaultTheme.vaultBlue,
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1F4D3A)),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1F4D3A)),
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF6E6A5E),
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
