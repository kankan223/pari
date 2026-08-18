import 'karma_action.dart';
import 'karma_event.dart';

/// The append-only karma event ledger (port, Task 10.2).
///
/// Offline-first + auditable: every karma action is persisted as a
/// hash-chained [KarmaEvent] BEFORE anything else; the balance is always a
/// deterministic projection of the chain (never a separately-mutated
/// counter). There is NO update or delete API — the ledger is append-only
/// by construction, and [verifyIntegrity] recomputes the whole chain so any
/// tampering is detectable.
///
/// SECURITY CHECKPOINT (10.2): events carry only the validated 64-hex
/// blind hash + the fixed action + the running balance + a timestamp.
/// Zero names, phones, emails, or payload bytes ever enter the ledger.
abstract class KarmaRepository {
  /// The current karma balance (the last event's [KarmaEvent.balanceAfter],
  /// or 0 for an empty ledger).
  Future<int> balance();

  /// Every ledger event, oldest-first (seq order).
  Future<List<KarmaEvent>> events();

  /// Appends a karma event for [action] by actor [actorHash] (a validated
  /// 64-hex blind hash) at [at] (defaults to now), minting a UUID v4
  /// event id and linking the hash chain. Returns the appended event.
  ///
  /// Throws [ArgumentError] for a malformed (non-64-hex) actor hash.
  Future<KarmaEvent> record({
    required KarmaAction action,
    required String actorHash,
    DateTime? at,
  });

  /// Recomputes every event's selfHash over its canonical bytes and checks
  /// the chain links (prevHash continuity + exactly-next sequence). False
  /// when ANY event was modified, removed, inserted, or reordered.
  Future<bool> verifyIntegrity();
}
