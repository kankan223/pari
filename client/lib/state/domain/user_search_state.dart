import '../../repository/domain/username_lookup_result.dart';

/// Immutable BLoC state for the username search flow (Task 6.2).
class UserSearchState {
  final UserSearchStatus status;

  /// The resolved user when [status] is [UserSearchStatus.found].
  final UsernameLookupResult? result;

  const UserSearchState({
    this.status = UserSearchStatus.idle,
    this.result,
  });

  const UserSearchState.idle() : this();

  const UserSearchState.searching() : this(status: UserSearchStatus.searching);

  const UserSearchState.found(UsernameLookupResult this.result)
      : status = UserSearchStatus.found;

  const UserSearchState.notFound() : this(status: UserSearchStatus.notFound);

  const UserSearchState.error() : this(status: UserSearchStatus.error);

  bool get isIdle => status == UserSearchStatus.idle;
  bool get isSearching => status == UserSearchStatus.searching;
  bool get isFound => status == UserSearchStatus.found;
  bool get isNotFound => status == UserSearchStatus.notFound;
  bool get isError => status == UserSearchStatus.error;
}

enum UserSearchStatus { idle, searching, found, notFound, error }
