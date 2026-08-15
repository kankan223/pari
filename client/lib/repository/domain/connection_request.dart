/// A Vault connection request (domain entity, Task 6.2).
///
/// Mirrors the `connection_requests` table in `AppSchema`:
/// - [requesterHash] / [recipientHash] are blind hashes (Argon2id of the
///   parties' phone numbers) — NEVER raw phone numbers, NEVER usernames.
/// - [status] follows the relay's state machine (Task 4.4):
///   `pending → accepted | rejected | withdrawn | expired`.
///
/// SECURITY CONTRACT: both hash fields are flagged sensitive in the schema
/// and only ever stored as opaque blind-hash values inside the encrypted
/// SQLCipher database. The local repository enforces the same single-
/// transition rule as the server (CAS: only `pending` may transition).
class ConnectionRequest {
  final String id;
  final String requesterHash;
  final String recipientHash;
  final ConnectionRequestStatus status;

  const ConnectionRequest({
    required this.id,
    required this.requesterHash,
    required this.recipientHash,
    required this.status,
  });

  ConnectionRequest copyWith({ConnectionRequestStatus? status}) =>
      ConnectionRequest(
        id: id,
        requesterHash: requesterHash,
        recipientHash: recipientHash,
        status: status ?? this.status,
      );
}

/// Lifecycle state of a connection request (mirrors the relay, Task 4.4).
enum ConnectionRequestStatus {
  pending,
  accepted,
  rejected,
  withdrawn,
  expired;

  /// Whether this state is final (no further transitions are legal).
  bool get isTerminal => this != ConnectionRequestStatus.pending;

  String get wireName => switch (this) {
        ConnectionRequestStatus.pending => 'pending',
        ConnectionRequestStatus.accepted => 'accepted',
        ConnectionRequestStatus.rejected => 'rejected',
        ConnectionRequestStatus.withdrawn => 'withdrawn',
        ConnectionRequestStatus.expired => 'expired',
      };

  static ConnectionRequestStatus fromWireName(String name) => switch (name) {
        'pending' => ConnectionRequestStatus.pending,
        'accepted' => ConnectionRequestStatus.accepted,
        'rejected' => ConnectionRequestStatus.rejected,
        'withdrawn' => ConnectionRequestStatus.withdrawn,
        'expired' => ConnectionRequestStatus.expired,
        _ => throw ArgumentError('Unknown connection request status: $name'),
      };
}
