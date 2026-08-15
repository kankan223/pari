/// Formats a linked device UUID into a stable, NON-PII display handle
/// (Task 6.5).
///
/// Device UUIDs are random identifiers (not PII by themselves), but the
/// device-management UI follows the same rule as peer handles: never render
/// a raw identifier that could be copied or shoulder-surfed. This renders a
/// deterministic `@dev_` + first 6 hex chars of the UUID.
///
/// SECURITY CHECKPOINT (Task 6.5): this is the ONLY device-identity
/// formatter the pairing UI may use. It renders `@dev_` + a 6-char fragment
/// — never the full UUID, never a phone, never a username, never a blind
/// hash.
String formatDeviceHandle(String deviceId) {
  final trimmed = deviceId.trim().toLowerCase();
  final fragment = trimmed.length >= 6 ? trimmed.substring(0, 6) : trimmed;
  return '@dev_$fragment';
}
