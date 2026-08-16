import 'package:civic_commons/geo/domain/explore_radius.dart';
import 'package:civic_commons/geo/domain/geo_place.dart';
import 'package:civic_commons/geo/domain/pin_code.dart';
import 'package:civic_commons/geo/domain/pin_code_resolver.dart';
import 'package:civic_commons/geo/domain/pin_code_store.dart';
import 'package:civic_commons/state/data/local_ledger_geo_bloc.dart';
import 'package:civic_commons/state/domain/ledger_geo_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _patna = GeoPlace(
  pinCode: PinCode.forTest('800001'),
  district: 'Patna',
  locality: 'Sadar',
);

final _bangalore = GeoPlace(
  pinCode: PinCode.forTest('560001'),
  district: 'Bengaluru Urban',
);

/// Scripted fake [PinCodeResolver].
class _FakeResolver implements PinCodeResolver {
  _FakeResolver(this._resolution);

  final PinCodeResolution _resolution;
  Object? _error;
  int calls = 0;

  void failWith(Object error) {
    _error = error;
  }

  @override
  Future<PinCodeResolution> resolveCurrentPlace() async {
    calls++;
    final error = _error;
    if (error != null) {
      throw error;
    }
    return _resolution;
  }
}

class _EmptyStore implements PinCodeStore {
  GeoPlace? place;
  int writes = 0;

  @override
  Future<GeoPlace?> read() async => place;

  @override
  Future<void> write(GeoPlace place) async {
    this.place = place;
    writes++;
  }
}

/// A pre-seeded store (persisted-pin path).
class _SeededStore implements PinCodeStore {
  _SeededStore(this.place);

  GeoPlace? place;

  @override
  Future<GeoPlace?> read() async => place;

  @override
  Future<void> write(GeoPlace place) async {
    this.place = place;
  }
}

void main() {
  group('LedgerGeoBloc (Task 7.2)', () {
    test('location path: resolves a coarse place and persists it', () async {
      final resolver = _FakeResolver(PinCodeResolution(
        place: _patna,
        source: PinCodeResolutionSource.location,
      ));
      final store = _EmptyStore();
      final bloc = LocalLedgerGeoBloc(resolver: resolver, store: store);
      final states = <LedgerGeoState>[];
      final sub = bloc.state.listen(states.add);

      await bloc.start();
      await pumpEventQueue();

      expect(resolver.calls, 1);
      expect(states.last.phase, LedgerGeoPhase.resolved);
      expect(states.last.pinCode, '800001');
      expect(states.last.place!.scopeLine, 'Sadar · Patna · 800001');
      expect(store.place!.pinCode.value, '800001');
      await sub.cancel();
      await bloc.close();
    });

    test('persisted pin wins (offline-first) — no location round-trip',
        () async {
      final resolver = _FakeResolver(PinCodeResolution(
        place: _patna,
        source: PinCodeResolutionSource.location,
      ));
      final bloc = LocalLedgerGeoBloc(
        resolver: resolver,
        store: _SeededStore(_bangalore),
      );
      final states = <LedgerGeoState>[];
      final sub = bloc.state.listen(states.add);

      await bloc.start();
      await pumpEventQueue();

      expect(resolver.calls, 0, reason: 'persisted pin avoids geolocation');
      expect(states.last.pinCode, '560001');
      expect(states.last.place!.district, 'Bengaluru Urban');
      await sub.cancel();
      await bloc.close();
    });

    test('permission/error degrades to manual entry with a generic flag',
        () async {
      final resolver = _FakeResolver(PinCodeResolution(
        place: _patna,
        source: PinCodeResolutionSource.location,
      ))
        ..failWith(
            const PinCodeResolutionException('location_permission_denied'));
      final bloc = LocalLedgerGeoBloc(resolver: resolver, store: _EmptyStore());
      final states = <LedgerGeoState>[];
      final sub = bloc.state.listen(states.add);

      await bloc.start();
      await pumpEventQueue();

      expect(states.last.phase, LedgerGeoPhase.manualEntryRequired);
      expect(states.last.hasError, isTrue);
      expect(states.last.pinCode, '');
      // No reason-specific detail in state.
      expect(
        states.last.toString().contains('permission'),
        isFalse,
      );
      await sub.cancel();
      await bloc.close();
    });

    test('unexpected resolver errors also degrade (never crash)', () async {
      final resolver = _FakeResolver(PinCodeResolution(
        place: _patna,
        source: PinCodeResolutionSource.location,
      ))
        ..failWith(Exception('boom'));
      final bloc = LocalLedgerGeoBloc(resolver: resolver, store: _EmptyStore());
      final states = <LedgerGeoState>[];
      final sub = bloc.state.listen(states.add);

      await bloc.start();
      await pumpEventQueue();

      expect(states.last.phase, LedgerGeoPhase.manualEntryRequired);
      expect(states.last.hasError, isTrue);
      await sub.cancel();
      await bloc.close();
    });

    test('setManualPin resolves and persists the entered pin', () async {
      final bloc = LocalLedgerGeoBloc(
        resolver: _FakeResolver(PinCodeResolution(
          place: _patna,
          source: PinCodeResolutionSource.location,
        )),
        store: _EmptyStore(),
      );
      final states = <LedgerGeoState>[];
      final sub = bloc.state.listen(states.add);

      await bloc.setManualPin(_bangalore);
      await pumpEventQueue();

      expect(states.last.phase, LedgerGeoPhase.resolved);
      expect(states.last.pinCode, '560001');
      expect(states.last.hasError, isFalse);
      await sub.cancel();
      await bloc.close();
    });

    test('setRadius expands/narrows the explore scope', () async {
      final bloc = LocalLedgerGeoBloc(
        resolver: _FakeResolver(PinCodeResolution(
          place: _patna,
          source: PinCodeResolutionSource.location,
        )),
        store: _EmptyStore(),
      );
      final states = <LedgerGeoState>[];
      final sub = bloc.state.listen(states.add);

      await bloc.setRadius(ExploreRadius.district10km);
      await pumpEventQueue();

      expect(states.last.radius, ExploreRadius.district10km);
      await bloc.setRadius(ExploreRadius.none);
      await pumpEventQueue();
      expect(states.last.radius, ExploreRadius.none);
      await sub.cancel();
      await bloc.close();
    });

    test('retryResolve re-attempts location after a failure', () async {
      final resolver = _FakeResolver(PinCodeResolution(
        place: _patna,
        source: PinCodeResolutionSource.location,
      ));
      final bloc = LocalLedgerGeoBloc(resolver: resolver, store: _EmptyStore());
      final states = <LedgerGeoState>[];
      final sub = bloc.state.listen(states.add);

      await bloc.retryResolve();
      await pumpEventQueue();

      expect(resolver.calls, 1);
      expect(states.last.phase, LedgerGeoPhase.resolved);
      await sub.cancel();
      await bloc.close();
    });
  });
}
