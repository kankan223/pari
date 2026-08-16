import '../../geo/domain/explore_radius.dart';
import '../../geo/domain/geo_place.dart';
import 'ledger_geo_state.dart';

/// BLoC for the Ledger geographic scope (Task 7.2).
///
/// Owns the coarse pin-code scope that the feed and compose screens are
/// driven by: it resolves the current place from device location (through
/// the [PinCodeResolver] port), falls back to the persisted pin or manual
/// entry, and tracks the Explore Nearby radius. The UI binds to [state]
/// and never touches location APIs directly.
///
/// SECURITY CHECKPOINT (Task 7.2): only the coarse [GeoPlace] ever reaches
/// state — coordinates never cross the data-layer boundary.
abstract class LedgerGeoBloc {
  /// Stream of geo-scope states.
  Stream<LedgerGeoState> get state;

  /// Resolves the scope: persisted pin first, then device location.
  Future<void> start();

  /// Retries device-location resolution (e.g. after granting permission).
  Future<void> retryResolve();

  /// Records a manually entered pin (manual fallback path).
  Future<void> setManualPin(GeoPlace place);

  /// Expands / narrows the Explore Nearby radius.
  Future<void> setRadius(ExploreRadius radius);

  /// Releases resources.
  Future<void> close();
}
