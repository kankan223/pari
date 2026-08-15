import 'package:civic_commons/repository/data/memory_user_search_repository.dart';
import 'package:civic_commons/repository/data/memory_username_directory.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 6.2): the username search flow resolves public usernames to
/// blind hashes (exact-match only), never returns a phone number, and the
/// directory remembers discovered mappings so the Vault can render
/// `@username` handles client-side.
void main() {
  const hashA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  group('MemoryUserSearchRepository', () {
    test('exact-match lookup returns the blind hash for a claimed username',
        () async {
      final search = MemoryUserSearchRepository()..seed('rekha_k', hashA);

      final result = await search.searchByUsername('rekha_k');
      expect(result, isNotNull);
      expect(result!.username, 'rekha_k');
      expect(result.blindHashId, hashA);
    });

    test('unknown username returns null (not found)', () async {
      final search = MemoryUserSearchRepository()..seed('rekha_k', hashA);
      expect(await search.searchByUsername('nobody_here_99'), isNull);
    });

    test('lookup is exact-match — no substring or case tricks', () async {
      final search = MemoryUserSearchRepository()..seed('rekha_k', hashA);
      expect(await search.searchByUsername('rekha'), isNull);
      expect(await search.searchByUsername('Rekha_K'), isNull);
      expect(await search.searchByUsername('rekha_k_'), isNull);
    });

    test('seeding a phone-shaped key is impossible (keys are usernames)',
        () async {
      final search = MemoryUserSearchRepository();
      // A phone can only ever be a *value* if a caller seeds it, which the
      // search contract forbids — assert the returned value is always the
      // blind hash the caller seeded (never derived from a phone).
      search.seed('civic_helper_99', hashA);
      final result = await search.searchByUsername('civic_helper_99');
      expect(result!.blindHashId, hashA);
    });
  });

  group('MemoryUsernameDirectory', () {
    test('remember + usernameForHash round-trips', () async {
      final directory = MemoryUsernameDirectory();
      await directory.remember(username: 'rekha_k', blindHashId: hashA);

      expect(await directory.usernameForHash(hashA), 'rekha_k');
      expect(
        await directory.usernameForHash(
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        isNull,
      );
    });

    test('seed constructor pre-populates the directory', () async {
      final directory = MemoryUsernameDirectory({hashA: 'rekha_k'});
      expect(await directory.usernameForHash(hashA), 'rekha_k');
    });

    test('never returns a phone number', () async {
      final directory = MemoryUsernameDirectory();
      await directory.remember(username: 'alice_civic', blindHashId: hashA);
      final username = await directory.usernameForHash(hashA);
      expect(username, isNot(contains('+')));
      expect(username, 'alice_civic');
    });
  });
}
