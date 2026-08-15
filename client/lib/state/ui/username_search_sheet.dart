import 'dart:async';

import 'package:flutter/material.dart';

import '../../security/domain/root_detection_service.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/connection_requests_bloc.dart';
import '../domain/user_search_bloc.dart';
import '../domain/user_search_state.dart';
import 'vault_theme.dart';

/// Username search sheet (DESIGN.md §6.4 Connection Request Gate).
///
/// A modal search flow: type a public username → search → the result is
/// shown with the RAW USERNAME (the shareable identifier, PRD §5.2) and the
/// derived non-PII handle — never the full blind hash, never a phone — and
/// a "Send connection request" action that creates a pending request via the
/// [ConnectionRequestsBloc].
///
/// SECURITY CHECKPOINT (Task 6.2): the widget consumes ONLY BLoC streams —
/// no repository/network access from the widget tree. The whole sheet is
/// wrapped in [SecureScreenWrapper] (FLAG_SECURE). No phone numbers, raw
/// blind hashes, or message content can appear in this tree (verified by
/// the 6.2 security scans).
class UsernameSearchSheet extends StatefulWidget {
  final UserSearchBloc searchBloc;
  final ConnectionRequestsBloc requestsBloc;
  final SecureFlagService? secureFlagService;
  final RootDetectionService? rootDetectionService;

  const UsernameSearchSheet({
    super.key,
    required this.searchBloc,
    required this.requestsBloc,
    this.secureFlagService,
    this.rootDetectionService,
  });

  /// Opens the sheet as a modal bottom sheet. Returns true when a request
  /// was successfully sent.
  static Future<bool> show(
    BuildContext context, {
    required UserSearchBloc searchBloc,
    required ConnectionRequestsBloc requestsBloc,
    SecureFlagService? secureFlagService,
    RootDetectionService? rootDetectionService,
  }) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => UsernameSearchSheet(
        searchBloc: searchBloc,
        requestsBloc: requestsBloc,
        secureFlagService: secureFlagService,
        rootDetectionService: rootDetectionService,
      ),
    );
    return sent ?? false;
  }

  @override
  State<UsernameSearchSheet> createState() => _UsernameSearchSheetState();
}

class _UsernameSearchSheetState extends State<UsernameSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _sentTargetHash;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String username) {
    final trimmed = username.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return;
    }
    unawaited(widget.searchBloc.search(trimmed));
  }

  Future<void> _sendRequest(String targetHash) async {
    setState(() => _sending = true);
    await widget.requestsBloc.sendRequest(targetHash);
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
      _sentTargetHash = targetHash;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _secure(
      SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'NEW CONNECTION',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: VaultTheme.vaultBlue,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Search by username…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _search(_controller.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: VaultTheme.vaultBlue,
                  ),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Search'),
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<UserSearchState>(
                stream: widget.searchBloc.state,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  return _buildSearchResult(context, state);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResult(BuildContext context, UserSearchState? state) {
    if (state == null || state.isIdle) {
      return const SizedBox(height: 8);
    }
    if (state.isSearching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: CircularProgressIndicator(color: VaultTheme.vaultBlue),
        ),
      );
    }
    if (state.isNotFound) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No user found with that username.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }
    if (state.isError) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Search unavailable. Try again.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }
    final result = state.result!;
    final sentTo = _sentTargetHash;
    final alreadySent = sentTo != null && sentTo == result.blindHashId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(
            radius: 16,
            backgroundColor: VaultTheme.vaultBlue,
            child: Icon(Icons.person_outline_rounded,
                color: Colors.white, size: 18),
          ),
          title: Text(
            '@${result.username}',
            style: theme().textTheme.bodyLarge?.copyWith(
                  fontFamily: VaultTheme.monoFont,
                  fontWeight: FontWeight.w600,
                ),
          ),
          subtitle: const Text('User found'),
        ),
        if (alreadySent)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: VaultTheme.vaultBlue, size: 18),
                SizedBox(width: 8),
                Text(
                  'Connection request sent',
                  style: TextStyle(color: VaultTheme.vaultBlue),
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  _sending ? null : () => _sendRequest(result.blindHashId),
              style: OutlinedButton.styleFrom(
                foregroundColor: VaultTheme.vaultBlue,
                side: const BorderSide(color: VaultTheme.vaultBlue),
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(_sending ? 'Sending…' : 'Send connection request'),
            ),
          ),
      ],
    );
  }

  ThemeData theme() => Theme.of(context);

  /// Wraps in [SecureScreenWrapper] (FLAG_SECURE), mirroring every Vault
  /// screen (Task 6.1 convention).
  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    final rootDetectionService = widget.rootDetectionService;
    return flag == null
        ? SecureScreenWrapper(
            rootDetectionService: rootDetectionService, child: child)
        : SecureScreenWrapper(
            secureFlagService: flag,
            rootDetectionService: rootDetectionService,
            child: child,
          );
  }
}
