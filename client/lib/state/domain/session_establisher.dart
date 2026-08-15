/// Port for establishing an X3DH session with a peer (Task 6.3).
///
/// Wired into the connection-approval hook deferred in Task 6.2: when a
/// pending connection request is accepted, the flow calls
/// [establishWith] with the requester's blind hash so the new connection is
/// immediately ready for encrypted messaging. Implementations MUST be keyed
/// by blind hash only and MUST NOT log or persist any PII.
abstract class SessionEstablisher {
  /// Establishes a session with the peer identified by [peerBlindHash]
  /// (a 64-hex blind hash). Idempotent: an existing session is reused.
  ///
  /// May throw when the peer has not published a prekey bundle — the caller
  /// decides whether that aborts the accept (it should not: the request is
  /// already persisted; a later sync run can retry establishment).
  Future<void> establishWith(String peerBlindHash);
}
