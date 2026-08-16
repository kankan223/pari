import 'geo_place.dart';

/// Persistence boundary for the user's chosen Ledger scope (Task 7.2).
///
/// Only the coarse [GeoPlace] (pin code + district/locality names) is
/// ever persisted — never coordinates. The production implementation is
/// SQLCipher-backed; the in-memory implementation serves tests and the
/// current local-first foundation.
///
/// SECURITY CHECKPOINT (Task 7.2): pin codes are public civic scopes, so
/// persistence here is safe by design — but the stored value must remain
/// a [GeoPlace] (no coordinates, no address strings).
abstract class PinCodeStore {
  /// The persisted place, or null on first run.
  Future<GeoPlace?> read();

  /// Persists [place] as the active scope.
  Future<void> write(GeoPlace place);
}
