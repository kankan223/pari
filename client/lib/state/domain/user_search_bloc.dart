import '../../repository/domain/username_lookup_result.dart';
import 'user_search_state.dart';

/// BLoC for the username search flow (Task 6.2).
///
/// The UI binds to [state] and calls [search] — it never talks to the
/// search repository or network directly.
///
/// SECURITY CHECKPOINT (Task 6.2): [UserSearchState] carries only the
/// resolved [UsernameLookupResult] (public username + blind hash). A phone
/// number can never appear in state; not-found and error states carry no
/// payload at all.
abstract class UserSearchBloc {
  /// Stream of search states (idle → searching → found | notFound | error).
  Stream<UserSearchState> get state;

  /// The cached list of users on the platform (accumulated across pages).
  List<UsernameLookupResult> get users;

  /// Whether more users are available to load.
  bool get hasMoreUsers;

  /// Searches for [username]. Emits searching, then found/notFound/error.
  Future<void> search(String username);

  /// Loads the first page of users from the server.
  Future<void> loadUsers();

  /// Loads the next page of users from the server.
  Future<void> loadMoreUsers();

  /// Returns to the idle state (clears the previous result).
  Future<void> clear();

  /// Releases resources.
  Future<void> close();
}
