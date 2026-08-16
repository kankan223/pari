import 'package:civic_commons/geo/domain/explore_radius.dart';
import 'package:civic_commons/geo/domain/geo_place.dart';
import 'package:civic_commons/geo/domain/pin_code.dart';
import 'package:civic_commons/geo/domain/pin_code_resolver.dart';
import 'package:civic_commons/geo/domain/pin_code_store.dart';
import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/state/data/local_ledger_feed_bloc.dart';
import 'package:civic_commons/state/data/local_ledger_geo_bloc.dart';
import 'package:civic_commons/state/ui/ledger_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _patna = GeoPlace(
  pinCode: PinCode.forTest('800001'),
  district: 'Patna',
  locality: 'Sadar',
);

class _ScriptedResolver implements PinCodeResolver {
  int calls = 0;

  @override
  Future<PinCodeResolution> resolveCurrentPlace() async {
    calls++;
    return PinCodeResolution(
      place: _patna,
      source: PinCodeResolutionSource.location,
    );
  }
}

class _MemStore implements PinCodeStore {
  GeoPlace? place;

  @override
  Future<GeoPlace?> read() async => place;

  @override
  Future<void> write(GeoPlace place) async {
    this.place = place;
  }
}

void main() {
  testWidgets(
      'feed shows the resolved scope line and Explore Nearby opens the '
      'radius sheet', (tester) async {
    final geoBloc = LocalLedgerGeoBloc(
      resolver: _ScriptedResolver(),
      store: _MemStore(),
    );
    final feedBloc = LocalLedgerFeedBloc(
      repository: InMemoryLedgerFeedRepository(seed: []),
    );
    ExploreRadius? changed;

    // The composition root starts the geo bloc (resolves the scope).
    await geoBloc.start();
    await tester.pumpWidget(MaterialApp(
      home: LedgerFeedScreen(
        bloc: feedBloc,
        pinCode: '800001',
        geoBloc: geoBloc,
        onRadiusChanged: (r) => changed = r,
      ),
    ));

    // Let both blocs settle.
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }

    // The coarse scope line appears (location-derived place).
    expect(find.text('Sadar · Patna · 800001'), findsOneWidget);
    expect(find.text('Explore Nearby'), findsOneWidget);

    // Open the sheet and pick 10 km.
    await tester.tap(find.text('Explore Nearby'));
    await tester.pumpAndSettle();
    expect(find.text('EXPLORE NEARBY'), findsOneWidget);
    expect(find.text('Local only'), findsOneWidget);

    await tester.tap(find.text('10 km'));
    await tester.pumpAndSettle();

    expect(changed, ExploreRadius.district10km);
    expect(geoBloc.state, isNotNull);

    await feedBloc.close();
    await geoBloc.close();
  });

  testWidgets('no geo bloc → Explore Nearby control is absent', (tester) async {
    final feedBloc = LocalLedgerFeedBloc(
      repository: InMemoryLedgerFeedRepository(seed: []),
    );
    await tester.pumpWidget(MaterialApp(
      home: LedgerFeedScreen(bloc: feedBloc, pinCode: '800001'),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(find.text('Explore Nearby'), findsNothing);
    await feedBloc.close();
  });
}
