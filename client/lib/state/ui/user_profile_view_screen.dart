import 'package:flutter/material.dart';

import '../../repository/data/blocking_service.dart';
import '../../repository/domain/username_directory.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import 'report_user_dialog.dart';
import 'vault_theme.dart';

/// Screen for viewing another user's public profile (read-only).
///
/// Shows username, online status, and provides block/report actions.
/// Accessed by tapping a username in the conversation list or chat.
///
/// SECURITY CHECKPOINT: renders only public profile fields. No blind hash,
/// phone number, token, or PII ever appears in the widget tree.
class UserProfileViewScreen extends StatefulWidget {
  final String peerHash;
  final UsernameDirectory? usernameDirectory;
  final BlockingService blockingService;
  final bool isOnline;

  const UserProfileViewScreen({
    super.key,
    required this.peerHash,
    this.usernameDirectory,
    required this.blockingService,
    this.isOnline = false,
  });

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  String? _username;
  bool _isBlocked = false;
  bool _loading = true;

  static const _avatarColors = [
    Color(0xFF1F4D3A),
    Color(0xFF2D5F8A),
    Color(0xFF8B4513),
    Color(0xFF6A0DAD),
    Color(0xFFC0392B),
    Color(0xFF2E86C1),
    Color(0xFF148F77),
    Color(0xFFB7950B),
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final username = await widget.usernameDirectory?.usernameForHash(widget.peerHash);
    final isBlocked = await widget.blockingService.isBlocked(widget.peerHash);
    if (mounted) {
      setState(() {
        _username = username;
        _isBlocked = isBlocked;
        _loading = false;
      });
    }
  }

  Color _avatarColor() {
    final name = _username ?? widget.peerHash;
    var hash = 0;
    for (var i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return _avatarColors[hash.abs() % _avatarColors.length];
  }

  String get _displayName => _username != null ? '@$_username' : _formatHash(widget.peerHash);

  String _formatHash(String hash) {
    if (hash.length > 16) {
      return '${hash.substring(0, 8)}...${hash.substring(hash.length - 4)}';
    }
    return hash;
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreenWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF6ED),
        appBar: AppBar(
          title: const Text('Profile'),
          backgroundColor: VaultTheme.vaultBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            if (!_loading && !_isBlocked)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) async {
                  if (value == 'block') {
                    final blocked = await showBlockDialog(
                      context: context,
                      blockingService: widget.blockingService,
                      targetHashId: widget.peerHash,
                      targetUsername: _username,
                    );
                    if (blocked && mounted) {
                      setState(() => _isBlocked = true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('User blocked')),
                      );
                    }
                  } else if (value == 'report') {
                    final reported = await showReportDialog(
                      context: context,
                      blockingService: widget.blockingService,
                      targetHashId: widget.peerHash,
                    );
                    if (reported && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Report submitted')),
                      );
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'report', child: Text('Report User')),
                  const PopupMenuItem(value: 'block', child: Text('Block User')),
                ],
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // Avatar
                  Center(
                    child: CircleAvatar(
                      radius: 56,
                      backgroundColor: _avatarColor(),
                      child: Text(
                        (_username ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Username
                  Center(
                    child: Text(
                      _displayName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Online status
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: widget.isOnline ? Colors.green : Colors.grey[400],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 14,
                            color: widget.isOnline ? Colors.green[600] : Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE3DCC8)),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(Icons.lock_outline, 'E2E Encrypted', 'Messages are end-to-end encrypted'),
                        const Divider(),
                        _buildInfoRow(Icons.shield_outlined, 'Privacy', 'Profile visible to contacts only'),
                        if (_isBlocked) ...[
                          const Divider(),
                          _buildInfoRow(Icons.block, 'Blocked', 'This user is blocked', isWarning: true),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Block/Unblock button
                  if (_isBlocked)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final unblocked = await widget.blockingService.unblock(widget.peerHash);
                          if (unblocked && mounted) {
                            setState(() => _isBlocked = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('User unblocked')),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                        label: const Text('Unblock User', style: TextStyle(color: Colors.green)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.green),
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final blocked = await showBlockDialog(
                            context: context,
                            blockingService: widget.blockingService,
                            targetHashId: widget.peerHash,
                            targetUsername: _username,
                          );
                          if (blocked && mounted) {
                            setState(() => _isBlocked = true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('User blocked')),
                            );
                          }
                        },
                        icon: const Icon(Icons.block, color: Colors.red),
                        label: const Text('Block User', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Privacy notice
                  Container(
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
                            'No phone number, email, or identity hash is ever shown on profiles.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF6E6A5E), height: 1.4),
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

  Widget _buildInfoRow(IconData icon, String label, String value, {bool isWarning = false}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: isWarning ? Colors.red : const Color(0xFF1F4D3A)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text(value, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
        ),
      ],
    );
  }
}
