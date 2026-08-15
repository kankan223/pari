import 'karma_cache.dart';
import 'non_sensitive_store.dart';

/// Canonical Hive box names (Task 3.6).
///
/// These three boxes hold NON-SENSITIVE data only and are opened unencrypted
/// by design. Sensitive data is barred from them by the [NonSensitiveGuard]
/// and lives only in the encrypted SQLCipher database / keychain.
abstract final class HiveBoxNames {
  static const String ledgerDrafts = 'ledger_drafts';
  static const String academyProgress = 'academy_progress';
  static const String karmaCache = 'karma_cache';
}

/// Port for Hive box lifecycle + typed accessors (Task 3.6).
///
/// The concrete implementation initializes Hive, opens the three canonical
/// non-sensitive boxes unencrypted, and opens any additional box through
/// [openSensitiveBox] with AES-256 encryption (key supplied by the injected
/// [HiveBoxKeyProvider]).
abstract class HiveBoxRegistry {
  /// Initializes Hive and opens all canonical boxes. Idempotent.
  Future<void> initialize();

  /// Closes every box this registry opened. Idempotent.
  Future<void> close();

  /// Whether [initialize] has completed.
  bool get isInitialized;

  /// The `ledger_drafts` box (non-sensitive draft metadata).
  NonSensitiveStore get ledgerDrafts;

  /// The `academy_progress` box (non-sensitive progress state).
  NonSensitiveStore get academyProgress;

  /// The `karma_cache` box with 5-minute TTL invalidation.
  KarmaCache get karmaCache;

  /// Opens (or returns an already-open) box with AES-256 encryption using the
  /// key from the injected key provider. Throws when no key is registered.
  ///
  /// SECURITY CHECKPOINT (Task 3.6): this is the ONLY path that stores data
  /// encrypted at rest — sensitive boxes must never be opened unencrypted.
  Future<NonSensitiveStore> openSensitiveBox(String name);
}
