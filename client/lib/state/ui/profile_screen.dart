import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../auth/auth_storage.dart';
import '../../auth/identity_api_client.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import 'vault_theme.dart';

/// User profile screen — view and edit avatar, status text, and visibility.
///
/// SECURITY CHECKPOINT: renders only public profile fields. No blind hash,
/// phone number, token, or PII ever appears in the widget tree.
/// Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class ProfileScreen extends StatefulWidget {
  final IdentityApiClient api;
  final AuthStorage storage;

  const ProfileScreen({
    super.key,
    required this.api,
    required this.storage,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _username;
  String? _avatarUrl;
  String _statusText = '';
  String _statusVisibility = 'online';
  bool _loading = true;
  bool _saving = false;
  final _statusController = TextEditingController();

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

  /// Safely read from storage — catches errors from FlutterSecureStorage
  /// in test environments or when the platform plugin is unavailable.
  Future<String?> _safeRead(Future<String?> Function() op) async {
    try {
      return await op();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadProfile() async {
    // Step 1: Try to get access token.
    final token = await _safeRead(() => widget.storage.getAccessToken());

    if (token == null || token.isEmpty) {
      // No token — show the profile UI with defaults.
      final username = await _safeRead(() => widget.storage.getUsername());
      if (mounted) {
        setState(() {
          _username = username;
          _loading = false;
        });
      }
      return;
    }

    // Step 2: Try loading from API.
    try {
      final profile = await widget.api.getMe(token);
      if (mounted) {
        setState(() {
          _username = profile.username;
          _avatarUrl = profile.avatarUrl;
          _statusText = profile.statusText ?? '';
          _statusVisibility = profile.statusVisibility ?? 'online';
          _statusController.text = _statusText;
          _loading = false;
        });
      }
      // Cache locally (non-critical).
      try {
        await widget.storage.saveAvatarUrl(_avatarUrl ?? '');
        await widget.storage.saveStatusText(_statusText);
        await widget.storage.saveStatusVisibility(_statusVisibility);
      } catch (_) {}
      return;
    } catch (_) {
      // API failed — fall through to cache.
    }

    // Step 3: Fall back to local cache.
    final username = await _safeRead(() => widget.storage.getUsername());
    final avatarUrl = await _safeRead(() => widget.storage.getAvatarUrl());
    final statusText = await _safeRead(() => widget.storage.getStatusText());
    final statusVis = await _safeRead(() => widget.storage.getStatusVisibility());
    if (mounted) {
      setState(() {
        _username = username;
        _avatarUrl = avatarUrl;
        _statusText = statusText ?? '';
        _statusVisibility = statusVis ?? 'online';
        _statusController.text = _statusText;
        _loading = false;
      });
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;

      final base64Data = base64Encode(file.bytes!);
      final ext = file.extension ?? 'png';
      final dataUrl = 'data:image/$ext;base64,$base64Data';

      setState(() => _avatarUrl = dataUrl);
      await _saveProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not pick image')),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final token = await _safeRead(() => widget.storage.getAccessToken());
      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      await widget.api.updateProfile(
        accessToken: token,
        avatarUrl: _avatarUrl ?? '',
        statusText: _statusController.text,
        statusVisibility: _statusVisibility,
      );

      try {
        await widget.storage.saveAvatarUrl(_avatarUrl ?? '');
        await widget.storage.saveStatusText(_statusController.text);
        await widget.storage.saveStatusVisibility(_statusVisibility);
      } catch (_) {}

      setState(() {
        _statusText = _statusController.text;
        _saving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated'),
            backgroundColor: Color(0xFF1F4D3A),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save profile')),
      );
    }
  }

  Color _avatarColor() {
    final name = _username ?? 'user';
    var hash = 0;
    for (var i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return _avatarColors[hash.abs() % _avatarColors.length];
  }

  @override
  void dispose() {
    _statusController.dispose();
    super.dispose();
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
            if (!_loading)
              TextButton(
                onPressed: _saving ? null : _saveProfile,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
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
                    child: GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: _avatarColor(),
                            backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                                ? MemoryImage(base64Decode(_avatarUrl!.split(',').last))
                                : null,
                            child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                                ? Text(
                                    (_username ?? 'U')[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: VaultTheme.vaultBlue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Tap to change avatar',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Username
                  _buildSectionHeader('USERNAME'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE3DCC8)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, color: Color(0xFF1F4D3A)),
                        const SizedBox(width: 12),
                        Text(
                          '@${_username ?? 'anonymous'}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Status text
                  _buildSectionHeader('STATUS'),
                  TextField(
                    controller: _statusController,
                    maxLength: 140,
                    decoration: InputDecoration(
                      hintText: 'What\'s on your mind?',
                      counterText: '${_statusController.text.length}/140',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE3DCC8)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE3DCC8)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: VaultTheme.vaultBlue, width: 2),
                      ),
                      prefixIcon: const Icon(Icons.edit_note, color: Color(0xFF1F4D3A)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 24),

                  // Visibility
                  _buildSectionHeader('VISIBILITY'),
                  _buildVisibilityOption('online', 'Online', Icons.circle, 'Others can see you\'re active'),
                  _buildVisibilityOption('away', 'Away', Icons.access_time, 'Show as idle'),
                  _buildVisibilityOption('invisible', 'Invisible', Icons.visibility_off_outlined, 'Appear offline to others'),
                  const SizedBox(height: 32),

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
                            'Your profile is visible to contacts only. '
                            'No phone number or identity hash is ever shown.',
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

  Widget _buildVisibilityOption(String value, String label, IconData icon, String description) {
    final isSelected = _statusVisibility == value;
    return GestureDetector(
      onTap: () => setState(() => _statusVisibility = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F0EB) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? VaultTheme.vaultBlue : const Color(0xFFE3DCC8),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? VaultTheme.vaultBlue : const Color(0xFF6E6A5E), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? VaultTheme.vaultBlue : Colors.black87,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: VaultTheme.vaultBlue, size: 20),
          ],
        ),
      ),
    );
  }
}
