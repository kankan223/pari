import '../../geo/domain/explore_radius.dart';
import '../../geo/domain/geo_place.dart';

/// Lifecycle of the Ledger geographic scope resolution (Task 7.2).
enum LedgerGeoPhase {
  /// No resolution attempted yet.
  idle,

  /// Resolving the current place from device location.
  resolving,

  /// A coarse place is active (location-derived, persisted, or manual).
  resolved,

  /// Location could not be used — the user must enter a pin manually.
  manualEntryRequired,
}

/// Immutable BLoC state for the Ledger geographic scope (Task 7.2).
///
/// SECURITY CHECKPOINT: the state carries ONLY the coarse [GeoPlace]
/// (pin code + district/locality names) — never coordinates. The
/// [pinCode] string is the finest signal that ever reaches the UI.
class LedgerGeoState {
  final LedgerGeoPhase phase;

  /// The active coarse place (null until resolved or when manual entry
  /// is required).
  final GeoPlace? place;

  /// Generic failure flag — never reason-specific (no side channel).
  final bool hasError;

  /// The Explore Nearby radius (Task 7.2); `none` = local-only feed.
  final ExploreRadius radius;

  const LedgerGeoState({
    this.phase = LedgerGeoPhase.idle,
    this.place,
    this.hasError = false,
    this.radius = ExploreRadius.none,
  });

  /// The active 6-digit pin code, or '' when unresolved.
  String get pinCode => place?.pinCode.value ?? '';

  bool get isResolved => phase == LedgerGeoPhase.resolved;

  LedgerGeoState copyWith({
    LedgerGeoPhase? phase,
    GeoPlace? place,
    bool clearPlace = false,
    bool? hasError,
    ExploreRadius? radius,
  }) =>
      LedgerGeoState(
        phase: phase ?? this.phase,
        place: clearPlace ? null : (place ?? this.place),
        hasError: hasError ?? this.hasError,
        radius: radius ?? this.radius,
      );
}
