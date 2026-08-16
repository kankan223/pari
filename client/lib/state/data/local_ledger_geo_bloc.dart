import 'dart:async';

import '../../geo/domain/explore_radius.dart';
import '../../geo/domain/geo_place.dart';
import '../../geo/domain/pin_code_resolver.dart';
import '../../geo/domain/pin_code_store.dart';
import '../domain/ledger_geo_bloc.dart';
import '../domain/ledger_geo_state.dart';

/// Local [LedgerGeoBloc] (data layer, Task 7.2).
///
/// Resolution order: persisted pin (offline-first) → device location
/// (coarse pin + district) → manual entry fallback. The resolved place is
/// persisted through the [PinCodeStore] so a subsequent cold start can
/// scope the feed without a location round-trip.
class LocalLedgerGeoBloc implements LedgerGeoBloc {
  final PinCodeResolver _resolver;
  final PinCodeStore _store;

  final StreamController<LedgerGeoState> _controller =
      StreamController<LedgerGeoState>.broadcast();

  LedgerGeoState _current = const LedgerGeoState();

  /// Monotonic sequence — a stale resolution can never overwrite a fresher
  /// one (codebase convention, cf. Task 6.2/7.1).
  int _seq = 0;

  LocalLedgerGeoBloc({
    required PinCodeResolver resolver,
    required PinCodeStore store,
  })  : _resolver = resolver,
        _store = store;

  @override
  Stream<LedgerGeoState> get state => _controller.stream;

  @override
  Future<void> start() async {
    _current = const LedgerGeoState(phase: LedgerGeoPhase.resolving);
    _controller.add(_current);

    // 1. Persisted pin first — offline-first, no location round-trip.
    final persisted = await _store.read();
    if (persisted != null) {
      _current = LedgerGeoState(
        phase: LedgerGeoPhase.resolved,
        place: persisted,
        radius: _current.radius,
      );
      _controller.add(_current);
      return;
    }

    // 2. Device location → coarse place.
    await _resolveFromLocation();
  }

  @override
  Future<void> retryResolve() async {
    _current = _current.copyWith(phase: LedgerGeoPhase.resolving);
    _controller.add(_current);
    await _resolveFromLocation();
  }

  @override
  Future<void> setManualPin(GeoPlace place) async {
    await _store.write(place);
    _current = LedgerGeoState(
      phase: LedgerGeoPhase.resolved,
      place: place,
      radius: _current.radius,
    );
    _controller.add(_current);
  }

  @override
  Future<void> setRadius(ExploreRadius radius) async {
    _current = _current.copyWith(radius: radius);
    _controller.add(_current);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  Future<void> _resolveFromLocation() async {
    final seq = ++_seq;
    try {
      final resolution = await _resolver.resolveCurrentPlace();
      if (seq != _seq) {
        return; // A newer resolution landed — drop this stale one.
      }
      await _store.write(resolution.place);
      _current = LedgerGeoState(
        phase: LedgerGeoPhase.resolved,
        place: resolution.place,
        radius: _current.radius,
      );
      _controller.add(_current);
    } on PinCodeResolutionException {
      if (seq != _seq) {
        return;
      }
      // Degrade gracefully: generic error, never reason-specific.
      _current = const LedgerGeoState(
        phase: LedgerGeoPhase.manualEntryRequired,
        hasError: true,
      );
      _controller.add(_current);
    } catch (_) {
      // Any unexpected failure also degrades to manual entry — the UI
      // must never crash on a location outage.
      if (seq != _seq) {
        return;
      }
      _current = const LedgerGeoState(
        phase: LedgerGeoPhase.manualEntryRequired,
        hasError: true,
      );
      _controller.add(_current);
    }
  }
}
