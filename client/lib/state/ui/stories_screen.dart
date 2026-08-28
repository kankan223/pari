import 'package:flutter/material.dart';

import 'vault_theme.dart';

/// Stories/status updates screen — users can post temporary updates
/// that expire after 24 hours, visible to their contacts.
class StoriesScreen extends StatefulWidget {
  final String currentUser;

  const StoriesScreen({super.key, required this.currentUser});

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  final List<Story> _stories = [
    Story(
      user: 'alice_dev',
      text: 'Working on a new community project! 🚀',
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      color: const Color(0xFF4CAF50),
    ),
    Story(
      user: 'bob_dev',
      text: 'Just completed the security audit ✅',
      timestamp: DateTime.now().subtract(const Duration(hours: 5)),
      color: const Color(0xFF2196F3),
    ),
    Story(
      user: 'civic_tester',
      text: 'Testing the new features today',
      timestamp: DateTime.now().subtract(const Duration(hours: 8)),
      color: const Color(0xFF9C27B0),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VaultTheme.vaultBg,
      appBar: AppBar(
        backgroundColor: VaultTheme.vaultBg,
        title: Text(
          'Stories',
          style: TextStyle(
            color: VaultTheme.vaultText,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add_circle_outline, color: VaultTheme.vaultBlue),
            onPressed: _showCreateStory,
          ),
        ],
      ),
      body: _stories.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_stories_outlined,
                      size: 64,
                      color: VaultTheme.vaultText.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text(
                    'No stories yet',
                    style: TextStyle(
                      color: VaultTheme.vaultText.withValues(alpha: 0.4),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share what you\'re up to!',
                    style: TextStyle(
                      color: VaultTheme.vaultText.withValues(alpha: 0.3),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _stories.length,
              itemBuilder: (_, i) {
                final story = _stories[i];
                final isOwn = story.user == widget.currentUser;
                final timeAgo = _formatTimeAgo(story.timestamp);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: isOwn
                        ? Border.all(
                            color: story.color.withValues(alpha: 0.3),
                            width: 2,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: story.color,
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  story.color.withValues(alpha: 0.15),
                              child: Text(
                                story.user[0].toUpperCase(),
                                style: TextStyle(
                                  color: story.color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '@${story.user}',
                                  style: TextStyle(
                                    color: VaultTheme.vaultText,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  timeAgo,
                                  style: TextStyle(
                                    color: VaultTheme.vaultText
                                        .withValues(alpha: 0.4),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isOwn)
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                color: VaultTheme.vaultText
                                    .withValues(alpha: 0.4),
                                size: 18,
                              ),
                              onSelected: (v) {
                                if (v == 'delete') {
                                  setState(() => _stories.removeAt(i));
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        story.text,
                        style: TextStyle(
                          color: VaultTheme.vaultText,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Reaction bar
                      Row(
                        children: [
                          _StoryAction(
                            icon: Icons.favorite_outline,
                            label: '0',
                            onTap: () {},
                          ),
                          const SizedBox(width: 16),
                          _StoryAction(
                            icon: Icons.chat_bubble_outline,
                            label: '0',
                            onTap: () {},
                          ),
                          const SizedBox(width: 16),
                          _StoryAction(
                            icon: Icons.share_outlined,
                            label: 'Share',
                            onTap: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _showCreateStory() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: VaultTheme.vaultCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New Story',
              style: TextStyle(
                color: VaultTheme.vaultText,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'What\'s on your mind?',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _stories.insert(
                        0,
                        Story(
                          user: widget.currentUser,
                          text: text,
                          timestamp: DateTime.now(),
                          color: VaultTheme.vaultBlue,
                        ),
                      );
                    });
                    Navigator.of(context).pop();
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: VaultTheme.vaultBlue,
                ),
                child: const Text('Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StoryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _StoryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 16, color: VaultTheme.vaultText.withValues(alpha: 0.4)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: VaultTheme.vaultText.withValues(alpha: 0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class Story {
  final String user;
  final String text;
  final DateTime timestamp;
  final Color color;

  const Story({
    required this.user,
    required this.text,
    required this.timestamp,
    this.color = const Color(0xFF2196F3),
  });
}
