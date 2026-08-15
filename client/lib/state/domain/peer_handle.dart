/// Formats a blind participant hash into a stable, NON-PII display handle.
///
/// The Vault shows ONLY a handle per peer (DESIGN §6: "Username shown as the
/// only identifier. No avatar, no profile photo."). Raw usernames are not yet
/// available client-side (they arrive with the connection-request / username
/// search flow in Task 6.2); until then every peer is addressed by a
/// DETERMINISTIC, derived handle that:
/// - is stable across restarts and devices (a pure function of the hash);
/// - never exposes the full 64-hex blind hash (a full hash rendered anywhere
///   could be copied or shoulder-surfed as an identifier — the UI security
///   scans forbid 64-hex strings in the widget tree);
/// - is one-way (a 6-hex fragment cannot be reversed into the hash or
///   fingerprinted back to the owner).
///
/// SECURITY CHECKPOINT (Task 6.1): this is the ONLY peer-identity formatter
/// the Vault UI may use. It renders `@peer_` + the first 6 hex characters of
/// the blind hash — never the raw hash, never a phone number, never an
/// e-mail, never a username.
String formatPeerHandle(String participantHash) {
  final trimmed = participantHash.trim().toLowerCase();
  final fragment = trimmed.length >= 6 ? trimmed.substring(0, 6) : trimmed;
  return '@peer_$fragment';
}
