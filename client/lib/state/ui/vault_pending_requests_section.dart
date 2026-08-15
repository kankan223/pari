import 'package:flutter/material.dart';

import '../domain/pending_request_summary.dart';
import '../domain/peer_handle.dart';
import 'vault_theme.dart';

/// PENDING REQUESTS queue section of the Vault conversation list
/// (DESIGN.md §6.2).
///
/// A collapsible header ("PENDING REQUESTS (N)") above one tile per incoming
/// request. Each tile shows the requester's display handle (rendered through
/// [formatPeerHandle] — never raw hashes/phones) and an Accept button.
///
/// SECURITY CHECKPOINT (Task 6.1): the section renders ONLY the count and the
/// derived display handle. Request ids, blind hashes, and any request message
/// body are never rendered here.
class VaultPendingRequestsSection extends StatefulWidget {
  const VaultPendingRequestsSection({
    super.key,
    required this.requests,
    this.onAccept,
  });

  final List<PendingRequestSummary> requests;

  /// Invoked with the request id when the user accepts an incoming request.
  /// Null renders the section READ-ONLY (no Accept buttons) — the inbox stays
  /// visible even before the accept flow is wired.
  final ValueChanged<String>? onAccept;

  @override
  State<VaultPendingRequestsSection> createState() =>
      _VaultPendingRequestsSectionState();
}

class _VaultPendingRequestsSectionState
    extends State<VaultPendingRequestsSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.requests.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'PENDING REQUESTS ($count)',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: VaultTheme.vaultBlue,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: VaultTheme.vaultBlue,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          for (final request in widget.requests)
            _RequestTile(request: request, onAccept: widget.onAccept),
      ],
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.onAccept});

  final PendingRequestSummary request;
  final ValueChanged<String>? onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accept = onAccept;
    // Task 6.2: a remembered PUBLIC username beats the derived handle;
    // the raw blind hash is never rendered either way.
    final username = request.requesterUsername;
    final handle = username != null
        ? '@$username'
        : formatPeerHandle(request.requesterHash);
    return ListTile(
      leading: const CircleAvatar(
        radius: 16,
        backgroundColor: VaultTheme.vaultBlue,
        child:
            Icon(Icons.person_outline_rounded, color: Colors.white, size: 18),
      ),
      title: Text(
        handle,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: VaultTheme.monoFont,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: const Text('wants to connect'),
      // Read-only when the accept flow is not yet wired.
      trailing: accept == null
          ? null
          : FilledButton(
              onPressed: () => accept(request.id),
              style: FilledButton.styleFrom(
                backgroundColor: VaultTheme.vaultBlue,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Accept'),
            ),
    );
  }
}
