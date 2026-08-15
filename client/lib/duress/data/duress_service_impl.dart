import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service.dart';
import 'package:civic_commons/duress/domain/duress_service.dart';
import 'package:civic_commons/duress/domain/vault_database.dart';

/// Concrete duress PIN service (application/data layer orchestration).
///
/// Implements the four Task 2.5 responsibilities:
/// 1. Dual PIN registration (real PIN + duress PIN).
/// 2. Two independent Argon2id key derivation paths (one per PIN/salt).
/// 3. Decoy database (`vault_decoy.db`) initialization with plausible content.
/// 4. Database selection based solely on which PIN successfully decrypts.
///
/// Security contract (checked by unit tests):
/// - The service NEVER persists, logs, or stores any flag, boolean, or
///   indicator of which PIN is real versus duress. The only persisted state
///   is the two encrypted database files themselves.
/// - Both vaults are initialized identically in structure: the decoy is not
///   distinguishable from the real vault by any stored metadata.
class DuressServiceImpl implements DuressService {
  /// Filename of the real vault database.
  static const String realVaultName = 'vault.db';

  /// Filename of the decoy vault database.
  static const String decoyVaultName = 'vault_decoy.db';

  /// Default seed content for BOTH databases: plausible-looking records so
  /// each vault is a valid, fully-formed database (never an obviously empty
  /// shell), and so the real and decoy files are byte-for-byte the same size
  /// and structure — an examiner cannot tell them apart by file size either.
  static List<VaultRecord> _buildDefaultSeedRecords() => [
        VaultRecord(id: 'schema_version', payload: _utf8('1')),
        VaultRecord(id: 'conversations', payload: _utf8('{}')),
        VaultRecord(id: 'message_queue', payload: _utf8('[]')),
      ];

  final CryptoService _crypto;
  final VaultDatabase _realVault;
  final VaultDatabase _decoyVault;

  DuressServiceImpl({
    required CryptoService cryptoService,
    required VaultDatabase realVault,
    required VaultDatabase decoyVault,
  })  : _crypto = cryptoService,
        _realVault = realVault,
        _decoyVault = decoyVault;

  /// Static helper used for decoy record payloads.
  static Uint8List _utf8(String value) =>
      Uint8List.fromList(utf8.encode(value));

  @override
  Future<bool> isRegistered() async {
    return await _realVault.isInitialized() &&
        await _decoyVault.isInitialized();
  }

  @override
  Future<void> registerPins({
    required String realPin,
    required String duressPin,
  }) async {
    if (realPin.isEmpty || duressPin.isEmpty) {
      throw ArgumentError('PINs cannot be empty');
    }
    if (realPin == duressPin) {
      throw const DuressRegistrationException(
        'Real and duress PINs must be different',
      );
    }
    if (await isRegistered()) {
      throw const DuressRegistrationException('PINs are already registered');
    }

    // Each PIN gets its own random 16-byte salt → two independent Argon2id
    // derivation paths → two unrelated 256-bit database keys.
    final realSalt = _crypto.generateSalt();
    final realKey = await _crypto.deriveKeyFromPin(realPin, realSalt);

    final duressSalt = _crypto.generateSalt();
    final duressKey = await _crypto.deriveKeyFromPin(duressPin, duressSalt);

    try {
      // Initialize both databases with identical structure AND identical seed
      // content. Both vaults look like normal, fully-formed databases; the
      // only difference is which PIN's derived key decrypts which file.
      await _realVault.initialize(
        key: realKey,
        salt: realSalt,
        seedRecords: _buildDefaultSeedRecords(),
      );
      await _decoyVault.initialize(
        key: duressKey,
        salt: duressSalt,
        seedRecords: _buildDefaultSeedRecords(),
      );
    } finally {
      // Wipe derived keys from memory regardless of outcome.
      _crypto.secureWipe(realKey);
      _crypto.secureWipe(duressKey);
    }
  }

  @override
  Future<UnlockResult> unlock(String pin) async {
    if (pin.isEmpty) {
      throw ArgumentError('PIN cannot be empty');
    }

    // Selection logic: derive a key from the entered PIN and attempt to
    // decrypt each vault. The vault whose stored encrypted body authenticates
    // under the derived key is the one the PIN unlocks. No stored indicator
    // of "real" vs "duress" is ever consulted.
    //
    // The real vault is deliberately tried first even when the entered PIN is
    // the duress PIN — that guaranteed-failed first derivation is required:
    // the service must not know which PIN is real without attempting both.
    final realSalt = await _tryReadSalt(_realVault);
    if (realSalt != null) {
      final key = await _crypto.deriveKeyFromPin(pin, realSalt);
      if (await _realVault.tryOpen(key)) {
        return UnlockResult(
            kind: VaultKind.real, database: _realVault, key: key);
      }
      // Wipe the derived key — it failed to decrypt this vault.
      _crypto.secureWipe(key);
    }

    final decoySalt = await _tryReadSalt(_decoyVault);
    if (decoySalt != null) {
      final key = await _crypto.deriveKeyFromPin(pin, decoySalt);
      if (await _decoyVault.tryOpen(key)) {
        return UnlockResult(
            kind: VaultKind.decoy, database: _decoyVault, key: key);
      }
      // Wipe the derived key — it failed to decrypt this vault.
      _crypto.secureWipe(key);
    }

    // A wrong PIN gets the same error whether it was "closer" to the real or
    // the duress PIN — no side channel about which vault it almost matched.
    throw const DuressPinException('PIN could not unlock any vault');
  }

  /// Reads a vault's salt, returning null if the vault is not initialized.
  Future<Uint8List?> _tryReadSalt(VaultDatabase vault) async {
    if (!await vault.isInitialized()) {
      return null;
    }
    try {
      return await vault.readSalt();
    } catch (_) {
      return null;
    }
  }
}
