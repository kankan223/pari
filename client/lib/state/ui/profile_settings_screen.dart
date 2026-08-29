import 'package:flutter/material.dart';

import 'vault_theme.dart';

/// Consolidated profile & settings screen — combines identity, karma,
/// consent, audit, security, and app settings into one scrollable screen.
class ProfileSettingsScreen extends StatefulWidget {
  final String username;
  final int karmaScore;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback? onLogout;

  const ProfileSettingsScreen({
    super.key,
    required this.username,
    this.karmaScore = 0,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.onLogout,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VaultTheme.vaultBg,
      body: CustomScrollView(
        slivers: [
          // ── Profile header ──
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    VaultTheme.vaultBlue.withValues(alpha: 0.08),
                    const Color(0xFF1F4D3A).withValues(alpha: 0.05),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: VaultTheme.vaultBlue.withValues(alpha: 0.15),
                    child: Text(
                      widget.username.isNotEmpty
                          ? widget.username[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: VaultTheme.vaultBlue,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '@${widget.username}',
                    style: TextStyle(
                      color: VaultTheme.vaultText,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Karma: ${widget.karmaScore}',
                      style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Settings sections ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader('Account'),
                  _SettingsTile(
                    icon: Icons.person_outline,
                    title: 'Edit Profile',
                    subtitle: 'Change display name and bio',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.lock_outline,
                    title: 'Privacy',
                    subtitle: 'Manage who can see your profile',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.devices_outlined,
                    title: 'Linked Devices',
                    subtitle: 'Manage connected devices',
                    onTap: () {},
                  ),

                  const SizedBox(height: 20),
                  const _SectionHeader('Appearance'),
                  _ThemeModeTile(
                    currentMode: _themeMode,
                    onChanged: (mode) {
                      setState(() => _themeMode = mode);
                      widget.onThemeModeChanged?.call(mode);
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.text_fields,
                    title: 'Font Size',
                    subtitle: 'Default',
                    onTap: () {},
                  ),

                  const SizedBox(height: 20),
                  _SectionHeader('Notifications'),
                  _SettingsTile(
                    icon: Icons.notifications_outlined,
                    title: 'Push Notifications',
                    subtitle: 'Messages, alerts, and updates',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.volume_up_outlined,
                    title: 'Sound & Vibration',
                    subtitle: 'Configure alert sounds',
                    onTap: () {},
                  ),

                  const SizedBox(height: 20),
                  _SectionHeader('Security'),
                  _SettingsTile(
                    icon: Icons.shield_outlined,
                    title: 'Two-Factor Authentication',
                    subtitle: 'Add extra security layer',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.fingerprint,
                    title: 'Biometric Lock',
                    subtitle: 'Use fingerprint or face ID',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.key_outlined,
                    title: 'Encryption Keys',
                    subtitle: 'View and manage E2E keys',
                    onTap: () {},
                  ),

                  const SizedBox(height: 20),
                  _SectionHeader('Data & Storage'),
                  _SettingsTile(
                    icon: Icons.storage_outlined,
                    title: 'Storage Usage',
                    subtitle: 'Manage local data',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.download_outlined,
                    title: 'Export Data',
                    subtitle: 'Download your data',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.delete_outline,
                    title: 'Delete Account',
                    subtitle: 'Permanently remove your data',
                    onTap: () {},
                    isDestructive: true,
                  ),

                  const SizedBox(height: 20),
                  _SectionHeader('About'),
                  _SettingsTile(
                    icon: Icons.info_outline,
                    title: 'Version',
                    subtitle: '1.0.0',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.description_outlined,
                    title: 'Terms of Service',
                    onTap: () {},
                  ),
                  _SettingsTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    onTap: () {},
                  ),

                  const SizedBox(height: 24),
                  // Logout button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text(
                        'Sign Out',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: VaultTheme.vaultText.withValues(alpha: 0.5),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.red : VaultTheme.vaultText;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        leading: Icon(icon, color: color.withValues(alpha: 0.7), size: 22),
        title: Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: TextStyle(
                  color: color.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              )
            : null,
        trailing: trailing ??
            Icon(
              Icons.chevron_right,
              color: color.withValues(alpha: 0.3),
              size: 20,
            ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
    );
  }
}

/// Three-option theme mode selector (System / Light / Dark).
class _ThemeModeTile extends StatelessWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeModeTile({
    required this.currentMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = VaultTheme.vaultText;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined,
                  color: color.withValues(alpha: 0.7), size: 22),
              const SizedBox(width: 12),
              Text(
                'Theme',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto, size: 16),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode, size: 16),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode, size: 16),
              ),
            ],
            selected: {currentMode},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) onChanged(selection.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
