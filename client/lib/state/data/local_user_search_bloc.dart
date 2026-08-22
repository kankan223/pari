import 'dart:async';

import '../../repository/domain/user_search_repository.dart';
import '../../repository/domain/username_directory.dart';
import '../../repository/domain/username_lookup_result.dart';
import '../domain/user_search_bloc.dart';
import '../domain/user_search_state.dart';

/// [UserSearchRepository]-backed [UserSearchBloc] (data layer, Task 6.2).
///
/// Runs the search through the injected [UserSearchRepository] port. On a
/// hit, the found mapping is remembered in the optional [UsernameDirectory]
/// so the Vault can render `@username` handles thereafter — making the raw
/// username available client-side without ever exposing the blind hash in
/// the UI tree.
class LocalUserSearchBloc implements UserSearchBloc {
  final UserSearchRepository _repository;
  final UsernameDirectory? _directory;
  final StreamController<UserSearchState> _controller =
      StreamController<UserSearchState>.broadcast();
  bool _closed = false;
  List<UsernameLookupResult> _users = [];

  LocalUserSearchBloc({
    required UserSearchRepository repository,
    UsernameDirectory? directory,
  })  : _repository = repository,
        _directory = directory;

  @override
  Stream<UserSearchState> get state => _controller.stream;

  @override
  List<UsernameLookupResult> get users => _users;

  @override
  Future<void> search(String username) async {
    if (_closed) {
      return;
    }
    _controller.add(const UserSearchState.searching());
    try {
      final result = await _repository.searchByUsername(username);
      if (_closed) {
        return;
      }
      if (result == null) {
        _controller.add(const UserSearchState.notFound());
        return;
      }
      final directory = _directory;
      if (directory != null) {
        await directory.remember(
          username: result.username,
          blindHashId: result.blindHashId,
        );
      }
      _controller.add(UserSearchState.found(result));
    } catch (_) {
      if (_closed) {
        return;
      }
      // Deliberately payload-free: network/directory failures never surface
      // PII or internal detail in state.
      _controller.add(const UserSearchState.error());
    }
  }

  @override
  Future<void> loadUsers() async {
    if (_closed) return;
    try {
      _users = await _repository.listUsers();
      // Remember all users in the directory for username resolution.
      final directory = _directory;
      if (directory != null) {
        for (final u in _users) {
          await directory.remember(username: u.username, blindHashId: u.blindHashId);
        }
      }
    } catch (_) {
      // Silently fail — user list is best-effort.
    }
  }

  @override
  Future<void> clear() async {
    if (!_closed) {
      _controller.add(const UserSearchState.idle());
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _controller.close();
  }
}
