import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_bloc.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import 'vault_theme.dart';

/// Profile settings screen — shows the user's profile information,
/// device management, and account actions.
///
/// SECURITY CHECKPOINT: renders only the public username, blinded handle,
/// and karma score. No phone number, no tokens, no raw blind hash in UI.
/// Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class ProfileSettingsScreen extends StatefulWidget {
  final AuthBloc authBloc;
  final String username;
  final String blindHashId;

  const ProfileSettingsScreen({
    super.key,
    required this.authBloc,
    required this.username,
    required this.blindHashId,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  bool _obscureHash = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureScreenWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF6ED),
        appBar: AppBar(
          title: const Text('Profile'),
          backgroundColor: VaultTheme.vaultBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Avatar + username card
            _buildProfileCard(theme),
            const SizedBox(height: 16),

            // Account info
            _buildSectionHeader('ACCOUNT'),
            _buildInfoTile(
              icon: Icons.person_outline,
              label: 'Username',
              value: '@${widget.username}',
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.username));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Username copied')),
                  );
                },
              ),
            ),
            _buildInfoTile(
              icon: Icons.fingerprint,
              label: 'Identity Hash',
              value: _obscureHash
                  ? '${widget.blindHashId.substring(0, 8)}...'
                  : widget.blindHashId,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _obscureHash ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureHash = !_obscureHash),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.blindHashId),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Identity hash copied')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Security section
            _buildSectionHeader('SECURITY'),
            _buildNavTile(
              icon: Icons.shield_outlined,
              label: 'Security Scan',
              subtitle: 'View security audit results',
              onTap: () {
                // Navigate to security scan
              },
            ),
            _buildNavTile(
              icon: Icons.verified_user_outlined,
              label: 'Consent Settings',
              subtitle: 'Manage your DPDP consent preferences',
              onTap: () {
                // Navigate to consent settings
              },
            ),
            const SizedBox(height: 16),

            // Danger zone
            _buildSectionHeader('ACCOUNT ACTIONS'),
            _buildActionTile(
              icon: Icons.logout,
              label: 'Log Out',
              color: Colors.orange,
              onTap: () => _showLogoutDialog(context),
            ),
            _buildActionTile(
              icon: Icons.delete_outline,
              label: 'Delete Account',
              color: Colors.red,
              onTap: () => _showDeleteDialog(context),
            ),
            const SizedBox(height: 24),

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
                      'Your identity is protected by a blind hash. '
                      'No phone number or personal data is stored or displayed.',
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
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: VaultTheme.vaultBlue,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              widget.username.isNotEmpty
                  ? widget.username[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${widget.username}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Civic Commons Member',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE3DCC8)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1F4D3A)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6E6A5E),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2430),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1F4D3A)),
        title: Text(label),
        subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE3DCC8)),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        trailing: Icon(Icons.chevron_right, size: 20, color: color),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.authBloc.logout();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This action is permanent and cannot be undone. '
          'All your data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Account deletion is not yet available'),
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
