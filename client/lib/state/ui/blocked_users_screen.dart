import 'package:flutter/material.dart';

import '../../repository/data/blocking_service.dart';
import '../../repository/domain/username_directory.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import 'vault_theme.dart';

/// Screen showing all blocked users with option to unblock.
///
/// SECURITY CHECKPOINT: renders only blind_hash_ids (truncated for display)
/// and resolved usernames. No PII, no tokens, no phone numbers.
class BlockedUsersScreen extends StatefulWidget {
  final BlockingService blockingService;
  final UsernameDirectory? usernameDirectory;

  const BlockedUsersScreen({
    super.key,
    required this.blockingService,
    this.usernameDirectory,
  });

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  Set<String> _blockedUsers = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBlocked();
  }

  Future<void> _loadBlocked() async {
    final blocked = await widget.blockingService.loadBlocked();
    if (mounted) {
      setState(() {
        _blockedUsers = blocked;
        _loading = false;
      });
    }
  }

  Future<void> _unblockUser(String hashId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unblock User'),
        content: const Text(
          'This user will be able to message you again. '
          'Are you sure you want to unblock them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unblock', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.blockingService.unblock(hashId);
      await _loadBlocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreenWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF6ED),
        appBar: AppBar(
          title: const Text('Blocked Users'),
          backgroundColor: VaultTheme.vaultBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _blockedUsers.isEmpty
                ? _buildEmptyState()
                : _buildBlockedList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No blocked users',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Users you block won\'t be able to\nsend you messages.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedList() {
    final hashes = _blockedUsers.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: hashes.length,
      itemBuilder: (context, index) {
        final hashId = hashes[index];
        final shortHash = '${hashId.substring(0, 8)}...${hashId.substring(hashId.length - 4)}';
        return FutureBuilder<String?>(
          future: widget.usernameDirectory?.usernameForHash(hashId),
          builder: (context, snapshot) {
            final username = snapshot.data;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE3DCC8)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFE8E0D0),
                    child: Icon(Icons.person_off, color: Colors.grey[400]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username != null ? '@$username' : shortHash,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (username == null)
                          Text(
                            shortHash,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _unblockUser(hashId),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('Unblock'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
