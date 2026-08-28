import 'package:flutter/material.dart';

import 'vault_theme.dart';

/// Home dashboard — aggregates War Room alerts, identity status, karma tier,
/// and quick-action cards into a single scrollable feed.
class HomeScreen extends StatelessWidget {
  final String username;
  final int karmaScore;
  final int unreadMessages;
  final int activeCases;
  final VoidCallback? onOpenWarRoom;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenAcademy;
  final VoidCallback? onOpenProfile;

  const HomeScreen({
    super.key,
    required this.username,
    this.karmaScore = 0,
    this.unreadMessages = 0,
    this.activeCases = 0,
    this.onOpenWarRoom,
    this.onOpenMessages,
    this.onOpenAcademy,
    this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    // Simple tier from score
    final tierColor = karmaScore >= 500
        ? const Color(0xFF1C1C2E)
        : karmaScore >= 150
            ? VaultTheme.vaultBlue
            : karmaScore >= 100
                ? const Color(0xFFD4870F)
                : karmaScore >= 50
                    ? const Color(0xFFD4870F)
                    : const Color(0xFF6B6B7A);
    final tierIcon = karmaScore >= 500
        ? Icons.hexagon_outlined
        : karmaScore >= 150
            ? Icons.stars_outlined
            : karmaScore >= 50
                ? Icons.check_circle_outline
                : Icons.circle_outlined;
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Scaffold(
      backgroundColor: VaultTheme.vaultBg,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──
          SliverAppBar(
            floating: true,
            backgroundColor: VaultTheme.vaultBg,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, @$username',
                  style: TextStyle(
                    color: VaultTheme.vaultText,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Civic Commons',
                  style: TextStyle(
                    color: VaultTheme.vaultText.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              // Karma badge
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tierColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tierIcon, size: 14, color: tierColor),
                    const SizedBox(width: 4),
                    Text(
                      '$karmaScore',
                      style: TextStyle(
                        color: tierColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Notifications badge
              if (unreadMessages > 0)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: Icon(Icons.notifications_outlined,
                          color: VaultTheme.vaultText),
                      onPressed: onOpenMessages,
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$unreadMessages',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Quick stats ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  _StatCard(
                    icon: Icons.shield_outlined,
                    label: 'Active Cases',
                    value: '$activeCases',
                    color: const Color(0xFFB45309),
                    onTap: onOpenWarRoom,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    icon: Icons.lock_outline,
                    label: 'Messages',
                    value: '$unreadMessages',
                    color: VaultTheme.vaultBlue,
                    onTap: onOpenMessages,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    icon: Icons.star_outline,
                    label: 'Karma',
                    value: '$karmaScore',
                    color: tierColor,
                    onTap: onOpenProfile,
                  ),
                ],
              ),
            ),
          ),

          // ── Quick actions ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Quick Actions',
                style: TextStyle(
                  color: VaultTheme.vaultText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.6,
                children: [
                  _ActionCard(
                    icon: Icons.shield,
                    title: 'Report Incident',
                    subtitle: 'File a new case',
                    color: const Color(0xFFB45309),
                    onTap: onOpenWarRoom,
                  ),
                  _ActionCard(
                    icon: Icons.chat_bubble_outline,
                    title: 'New Message',
                    subtitle: 'Start a conversation',
                    color: VaultTheme.vaultBlue,
                    onTap: onOpenMessages,
                  ),
                  _ActionCard(
                    icon: Icons.menu_book_outlined,
                    title: 'Learn',
                    subtitle: 'Browse courses',
                    color: const Color(0xFF4CAF50),
                    onTap: onOpenAcademy,
                  ),
                  _ActionCard(
                    icon: Icons.person_outline,
                    title: 'Profile',
                    subtitle: 'Settings & identity',
                    color: const Color(0xFF9C27B0),
                    onTap: onOpenProfile,
                  ),
                ],
              ),
            ),
          ),

          // ── Recent activity ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Recent Activity',
                style: TextStyle(
                  color: VaultTheme.vaultText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                children: [
                  _ActivityTile(
                    icon: Icons.info_outline,
                    title: 'Welcome to Civic Commons',
                    subtitle: 'Your privacy-first community platform',
                    time: 'Just now',
                    color: const Color(0xFF2196F3),
                  ),
                  const SizedBox(height: 8),
                  _ActivityTile(
                    icon: Icons.security,
                    title: 'End-to-end encryption active',
                    subtitle: 'All messages are secured',
                    time: '2m ago',
                    color: const Color(0xFF4CAF50),
                  ),
                  const SizedBox(height: 8),
                  _ActivityTile(
                    icon: Icons.verified_user,
                    title: 'Identity verified',
                    subtitle: 'Your account is secure',
                    time: '5m ago',
                    color: const Color(0xFF9C27B0),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
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
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  color: VaultTheme.vaultText,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: VaultTheme.vaultText.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                color: VaultTheme.vaultText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: VaultTheme.vaultText.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final Color color;

  const _ActivityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: VaultTheme.vaultText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: VaultTheme.vaultText.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(
              color: VaultTheme.vaultText.withValues(alpha: 0.4),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
