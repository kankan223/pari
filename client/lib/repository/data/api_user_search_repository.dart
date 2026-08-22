import '../../auth/user_search_api_client.dart';
import '../domain/user_list_result.dart';
import '../domain/user_search_repository.dart';
import '../domain/username_lookup_result.dart';

/// [UserSearchRepository] backed by the identity service API.
///
/// Delegates to [UserSearchApiClient] for the actual HTTP call.
/// Returns null when the username doesn't exist — never throws with PII.
///
/// SECURITY CHECKPOINT (Task 6.2): the repository never stores or logs
/// the raw search result beyond passing it to the caller. Phone numbers
/// never touch this layer.
class ApiUserSearchRepository implements UserSearchRepository {
  final UserSearchApiClient _api;
  final String Function() _tokenProvider;

  ApiUserSearchRepository({
    required UserSearchApiClient api,
    required String Function() tokenProvider,
  })  : _api = api,
        _tokenProvider = tokenProvider;

  @override
  Future<UsernameLookupResult?> searchByUsername(String username) async {
    final token = _tokenProvider();
    if (token.isEmpty) return null;
    return _api.searchByUsername(
      accessToken: token,
      username: username,
    );
  }

  @override
  Future<UserListResult> listUsers({int limit = 50, int offset = 0}) async {
    final token = _tokenProvider();
    if (token.isEmpty) {
      return const UserListResult(users: [], total: 0, hasMore: false);
    }
    return _api.listUsers(accessToken: token, limit: limit, offset: offset);
  }
}
