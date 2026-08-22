import 'package:civic_commons/repository/data/memory_user_search_repository.dart';
import 'package:civic_commons/repository/data/memory_username_directory.dart';
import 'package:civic_commons/repository/domain/user_search_repository.dart';
import 'package:civic_commons/repository/domain/username_lookup_result.dart';
import 'package:civic_commons/state/data/local_user_search_bloc.dart';
import 'package:civic_commons/state/domain/user_search_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 6.2): the username search BLoC runs the search through the
/// repository port, emits the found result (or notFound/error), remembers the
/// discovered mapping in the directory, and its state never carries PII.
void main() {
  const hashA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  group('LocalUserSearchBloc - search lifecycle', () {
    test('searching → found carries the resolved result', () async {
      final search = MemoryUserSearchRepository()..seed('rekha_k', hashA);
      final bloc = LocalUserSearchBloc(repository: search);

      final states = <UserSearchState>[];
      bloc.state.listen(states.add);
      await bloc.search('rekha_k');
      await flushMicrotasks();

      expect(states.map((s) => s.status),
          containsAll([UserSearchStatus.searching, UserSearchStatus.found]));
      expect(states.last.isFound, isTrue);
      expect(states.last.result!.username, 'rekha_k');
      expect(states.last.result!.blindHashId, hashA);

      await bloc.close();
    });

    test('unknown username emits notFound with no payload', () async {
      final search = MemoryUserSearchRepository();
      final bloc = LocalUserSearchBloc(repository: search);

      final states = <UserSearchState>[];
      bloc.state.listen(states.add);
      await bloc.search('nobody_here_99');
      await flushMicrotasks();

      expect(states.last.isNotFound, isTrue);
      expect(states.last.result, isNull);

      await bloc.close();
    });

    test('repository failure emits error with no payload', () async {
      final bloc = LocalUserSearchBloc(
        repository: _ThrowingSearchRepository(),
      );

      final states = <UserSearchState>[];
      bloc.state.listen(states.add);
      await bloc.search('rekha_k');
      await flushMicrotasks();

      expect(states.last.isError, isTrue);
      expect(states.last.result, isNull);

      await bloc.close();
    });

    test('clear() returns to idle', () async {
      final search = MemoryUserSearchRepository()..seed('rekha_k', hashA);
      final bloc = LocalUserSearchBloc(repository: search);

      final states = <UserSearchState>[];
      bloc.state.listen(states.add);
      await bloc.search('rekha_k');
      await bloc.clear();
      await flushMicrotasks();

      expect(states.last.isIdle, isTrue);

      await bloc.close();
    });
  });

  group('LocalUserSearchBloc - username availability (Task 6.2)', () {
    test('a found search remembers the username in the directory', () async {
      final search = MemoryUserSearchRepository()..seed('rekha_k', hashA);
      final directory = MemoryUsernameDirectory();
      final bloc = LocalUserSearchBloc(
        repository: search,
        directory: directory,
      );

      await bloc.search('rekha_k');
      await bloc.close();

      // The raw username is now available client-side for @-handles.
      expect(await directory.usernameForHash(hashA), 'rekha_k');
    });

    test('state never carries a phone-shaped value', () async {
      final search = MemoryUserSearchRepository()..seed('rekha_k', hashA);
      final bloc = LocalUserSearchBloc(repository: search);

      final states = <UserSearchState>[];
      bloc.state.listen(states.add);
      await bloc.search('rekha_k');

      for (final state in states) {
        expect(state.status, isNot(UserSearchStatus.error));
        final result = state.result;
        if (result != null) {
          expect(result.blindHashId, isNot(contains('+')));
          expect(result.username, isNot(contains('+')));
        }
      }
      await bloc.close();
    });
  });
}

class _ThrowingSearchRepository implements UserSearchRepository {
  @override
  Future<UsernameLookupResult?> searchByUsername(String username) async {
    throw StateError('search unavailable');
  }

  @override
  Future<List<UsernameLookupResult>> listUsers() async {
    throw StateError('search unavailable');
  }
}

/// Flushes pending microtasks so broadcast-stream deliveries land.
Future<void> flushMicrotasks() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
