/// UI-safe projection of a pending Vault connection request (Task 6.1).
///
/// Mirrors the `connection_requests` row for the INBOX of the current user:
/// an incoming request from [requesterHash] (a blind hash — never a raw
/// phone number) with a stable [id].
///
/// SECURITY CHECKPOINT (Task 6.1): this summary carries ONLY the request id
/// and the requester's 64-hex blind hash. No phone numbers, no usernames, no
/// message bodies — and the UI renders the requester exclusively through
/// [formatPeerHandle].
class PendingRequestSummary {
  final String id;
  final String requesterHash;

  /// The requester's PUBLIC username when known from the local directory
  /// (Task 6.2). Null renders the derived non-PII handle instead.
  final String? requesterUsername;

  const PendingRequestSummary({
    required this.id,
    required this.requesterHash,
    this.requesterUsername,
  });
}
