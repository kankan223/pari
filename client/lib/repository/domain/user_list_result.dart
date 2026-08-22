import 'username_lookup_result.dart';

/// A paginated result from the user-list endpoint (GET /v1/identity/users).
///
/// [users] is the current page of results, [total] is the total count of all
/// users on the platform, and [hasMore] indicates whether additional pages exist.
///
/// SECURITY CHECKPOINT: carries only public usernames and blind hashes — no
/// phone numbers, no device keys, no PII.
class UserListResult {
  final List<UsernameLookupResult> users;
  final int total;
  final bool hasMore;

  const UserListResult({
    required this.users,
    required this.total,
    required this.hasMore,
  });
}
