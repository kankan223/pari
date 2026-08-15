/// A username search result (Task 6.2).
///
/// [username] is the PUBLIC, shareable identifier the user searched for;
/// [blindHashId] is the owner's 64-hex blind hash — the only identifier the
/// messaging layer ever addresses peers by.
///
/// SECURITY CHECKPOINT (Task 6.2): this result carries NO phone number, no
/// e-mail, and no device key material. The UI renders the username and a
/// derived non-PII handle ([formatPeerHandle]) — never the raw blind hash.
class UsernameLookupResult {
  final String username;
  final String blindHashId;

  const UsernameLookupResult({
    required this.username,
    required this.blindHashId,
  });
}
