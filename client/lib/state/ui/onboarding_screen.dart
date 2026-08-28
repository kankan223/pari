import 'package:flutter/material.dart';

import 'vault_theme.dart';

/// Onboarding screen shown on first launch — 3 pages explaining
/// privacy, messaging, and community features.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPageData(
      icon: Icons.shield_outlined,
      title: 'Privacy First',
      description:
          'Your identity is protected with end-to-end encryption. '
          'No phone numbers, emails, or personal data are ever stored in plain text.',
      color: Color(0xFF1F4D3A),
    ),
    _OnboardingPageData(
      icon: Icons.chat_bubble_outline,
      title: 'Secure Messaging',
      description:
          'Send messages, files, and voice notes with confidence. '
          'Every conversation is encrypted and your data stays on your device.',
      color: Color(0xFF2196F3),
    ),
    _OnboardingPageData(
      icon: Icons.people_outline,
      title: 'Community',
      description:
          'Join study groups, share knowledge, and collaborate with '
          'your community. Earn karma for your contributions.',
      color: Color(0xFF9C27B0),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: widget.onComplete,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: VaultTheme.vaultText.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),

            // Page view
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: p.color.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(p.icon, size: 64, color: p.color),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          p.title,
                          style: TextStyle(
                            color: VaultTheme.vaultText,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: VaultTheme.vaultText.withValues(alpha: 0.6),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Dots + button
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  // Page indicators
                  ...List.generate(_pages.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 8),
                      width: _page == i ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _page == i
                            ? VaultTheme.vaultBlue
                            : VaultTheme.vaultText.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),

                  const Spacer(),

                  // Next / Get Started button
                  FilledButton(
                    onPressed: () {
                      if (_page < _pages.length - 1) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        widget.onComplete();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: VaultTheme.vaultBlue,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _page < _pages.length - 1 ? 'Next' : 'Get Started',
                      style: const TextStyle(fontSize: 15),
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
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}
