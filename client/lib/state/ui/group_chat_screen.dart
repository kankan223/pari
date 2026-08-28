import 'package:flutter/material.dart';

import '../../repository/domain/conversation.dart';
import '../../repository/domain/message.dart';
import 'vault_theme.dart';

/// Screen for creating a new group chat with selected members.
class CreateGroupScreen extends StatefulWidget {
  final List<String> availableUsers; // usernames
  final ValueChanged<GroupChat> onGroupCreated;

  const CreateGroupScreen({
    super.key,
    required this.availableUsers,
    required this.onGroupCreated,
  });

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final Set<String> _selectedUsers = {};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VaultTheme.vaultBg,
      appBar: AppBar(
        backgroundColor: VaultTheme.vaultBg,
        title: Text(
          'New Group',
          style: TextStyle(color: VaultTheme.vaultText),
        ),
        actions: [
          TextButton(
            onPressed: _selectedUsers.isEmpty
                ? null
                : () {
                    final group = GroupChat(
                      name: _nameController.text.isEmpty
                          ? 'Group (${_selectedUsers.length + 1})'
                          : _nameController.text,
                      members: {..._selectedUsers, 'You'},
                      createdAt: DateTime.now(),
                    );
                    widget.onGroupCreated(group);
                    Navigator.of(context).pop();
                  },
            child: Text(
              'Create',
              style: TextStyle(
                color: _selectedUsers.isEmpty
                    ? Colors.grey
                    : VaultTheme.vaultBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Group name input
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Group name (optional)',
                prefixIcon: const Icon(Icons.group_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Selected count
          if (_selectedUsers.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: VaultTheme.vaultBlue.withValues(alpha: 0.05),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: VaultTheme.vaultBlue, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedUsers.length} member${_selectedUsers.length > 1 ? 's' : ''} selected',
                    style: TextStyle(
                      color: VaultTheme.vaultBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // User list
          Expanded(
            child: ListView.builder(
              itemCount: widget.availableUsers.length,
              itemBuilder: (_, i) {
                final user = widget.availableUsers[i];
                final isSelected = _selectedUsers.contains(user);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedUsers.add(user);
                      } else {
                        _selectedUsers.remove(user);
                      }
                    });
                  },
                  secondary: CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        VaultTheme.vaultBlue.withValues(alpha: 0.1),
                    child: Text(
                      user[0].toUpperCase(),
                      style: TextStyle(
                        color: VaultTheme.vaultBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  title: Text(
                    '@$user',
                    style: TextStyle(
                      color: VaultTheme.vaultText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  activeColor: VaultTheme.vaultBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A group chat conversation.
class GroupChat {
  final String name;
  final Set<String> members;
  final DateTime createdAt;
  final String id;

  GroupChat({
    required this.name,
    required this.members,
    required this.createdAt,
    String? id,
  }) : id = id ?? 'group_${DateTime.now().millisecondsSinceEpoch}';
}

/// Group chat detail screen showing messages and members.
class GroupChatScreen extends StatefulWidget {
  final GroupChat group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _controller = TextEditingController();
  final List<_GroupMessage> _messages = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_GroupMessage(
        sender: 'You',
        text: text,
        timestamp: DateTime.now(),
      ));
    });
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VaultTheme.vaultBg,
      appBar: AppBar(
        backgroundColor: VaultTheme.vaultBg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.group.name,
              style: TextStyle(
                color: VaultTheme.vaultText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${widget.group.members.length} members',
              style: TextStyle(
                color: VaultTheme.vaultText.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.people_outline, color: VaultTheme.vaultText),
            onPressed: () => _showMembers(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.group_outlined,
                            size: 48,
                            color: VaultTheme.vaultText.withValues(alpha: 0.2)),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            color: VaultTheme.vaultText.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Send a message to start the conversation',
                          style: TextStyle(
                            color: VaultTheme.vaultText.withValues(alpha: 0.3),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      final isMe = msg.sender == 'You';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe) ...[
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: VaultTheme.vaultBlue
                                    .withValues(alpha: 0.1),
                                child: Text(
                                  msg.sender[0].toUpperCase(),
                                  style: TextStyle(
                                    color: VaultTheme.vaultBlue,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        msg.sender,
                                        style: TextStyle(
                                          color: VaultTheme.vaultBlue,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? VaultTheme.vaultBlue
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.05),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      msg.text,
                                      style: TextStyle(
                                        color: isMe
                                            ? Colors.white
                                            : VaultTheme.vaultText,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isMe) const SizedBox(width: 8),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.withValues(alpha: 0.05),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: VaultTheme.vaultBlue,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMembers() {
    showModalBottomSheet(
      context: context,
      backgroundColor: VaultTheme.vaultCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Members (${widget.group.members.length})',
              style: TextStyle(
                color: VaultTheme.vaultText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...widget.group.members.map((member) => ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        VaultTheme.vaultBlue.withValues(alpha: 0.1),
                    child: Text(
                      member[0].toUpperCase(),
                      style: TextStyle(
                        color: VaultTheme.vaultBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  title: Text(
                    '@$member',
                    style: TextStyle(
                      color: VaultTheme.vaultText,
                      fontSize: 14,
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _GroupMessage {
  final String sender;
  final String text;
  final DateTime timestamp;

  const _GroupMessage({
    required this.sender,
    required this.text,
    required this.timestamp,
  });
}
