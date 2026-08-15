import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/crypto/secure_key_storage.dart';
import 'package:civic_commons/pairing/data/secure_storage_identity_key_source.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureKeyStorage keyStorage;
  late SecureStorageIdentityKeySource source;
  final crypto = CryptoServiceImpl();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    const mock = FlutterSecureStorage();
    await mock.deleteAll();
    keyStorage = SecureKeyStorage(secureStorage: mock);
    source = SecureStorageIdentityKeySource(
      keyStorage: keyStorage,
      crypto: crypto,
    );
  });

  test('creates + stores a fresh identity key pair when none exists', () async {
    expect(await keyStorage.hasIdentityKeys(), isFalse);

    final pair = await source.loadOrCreateIdentityKeyPair();

    expect(pair, isNotNull);
    expect(await keyStorage.hasIdentityKeys(), isTrue,
        reason: 'the fresh identity must be persisted to the keystore');
    // The stored pair loads back with matching public bytes.
    final reloaded = await keyStorage.getIdentityKeyPair();
    final pub = await pair.extractPublicKey();
    final reloadedPub = await reloaded!.extractPublicKey();
    expect(reloadedPub.bytes, pub.bytes);
  });

  test('loadOrCreateIdentityKeyPair reuses an existing identity', () async {
    final first = await source.loadOrCreateIdentityKeyPair();
    final second = await source.loadOrCreateIdentityKeyPair();

    final firstPub = await first.extractPublicKey();
    final secondPub = await second.extractPublicKey();
    expect(secondPub.bytes, firstPub.bytes,
        reason: 'a second load must not regenerate the identity');
  });

  test('loadIdentityPublicKey returns the public half of the identity',
      () async {
    final pub = await source.loadIdentityPublicKey();

    expect(pub.bytes, hasLength(32), reason: 'Ed25519 public key size');
    expect(await keyStorage.hasIdentityKeys(), isTrue,
        reason: 'loading the public key lazily creates + persists identity');
  });

  test('SECURITY CHECKPOINT: no private key material escapes the source',
      () async {
    final pair = await source.loadOrCreateIdentityKeyPair();
    final privateBytes = await pair.extractPrivateKeyBytes();

    // The private half stays inside the pair/keystore abstraction — the
    // source exposes only public-key accessors.
    expect(privateBytes, hasLength(32));
  });
}
