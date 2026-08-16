import 'package:civic_commons/geo/domain/explore_radius.dart';
import 'package:civic_commons/geo/domain/geo_place.dart';
import 'package:civic_commons/geo/domain/pin_code.dart';
import 'package:civic_commons/geo/domain/pin_code_resolver.dart';
import 'package:civic_commons/geo/domain/pin_code_store.dart';
import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/state/data/local_ledger_feed_bloc.dart';
import 'package:civic_commons/state/data/local_ledger_geo_bloc.dart';
import 'package:civic_commons/state/ui/ledger_feed_screen.dart';
import 'package:civic_commons/state/ui/nearby_badge_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _patna = GeoPlace(
  pinCode: PinCode.forTest('800001'),
  district: 'Patna',
  locality: 'Sadar',
);

class _ScriptedResolver implements PinCodeResolver {
  @override
  Future<PinCodeResolution> resolveCurrentPlace() async => PinCodeResolution(
        place: _patna,
        source: PinCodeResolutionSource.location,
      );
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

LedgerPost _post({
  required String id,
  String pinCode = '800001',
  String? district = 'Patna',
  required DateTime createdAt,
}) =>
    LedgerPost(
      id: id,
      category: LedgerCategory.civicInfrastructure,
      pinCode: pinCode,
      district: district,
      headline: 'Headline $id',
      body: 'Body $id',
      authorHandle: 'handle_$id',
      createdAt: createdAt,
    );

void main() {
  final now = DateTime.utc(2026, 8, 15, 12);

  testWidgets(
      'sheet radius selection drives the dynamic feed expansion end-to-end',
      (tester) async {
    final geoBloc = LocalLedgerGeoBloc(
      resolver: _ScriptedResolver(),
      store: _MemStore(),
    );
    final feedBloc = LocalLedgerFeedBloc(
      repository: InMemoryLedgerFeedRepository(
        seed: [
          _post(id: 'local', createdAt: now),
          _post(
              id: 'nearby',
              pinCode: '800002',
              district: 'Patna',
              createdAt: now),
        ],
      ),
    );
    ExploreRadius? changed;
    await tester.pumpWidget(MaterialApp(
      home: LedgerFeedScreen(
        bloc: feedBloc,
        pinCode: '800001',
        geoBloc: geoBloc,
        onRadiusChanged: (r) => changed = r,
      ),
    ));

    // Settle the feed + geo blocs.
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }

    // Local-only feed initially: no badge, no nearby strip.
    expect(find.byType(NearbyBadgeWidget), findsNothing);
    expect(find.textContaining('nearby pins'), findsNothing);

    // Open the sheet and select 10 km.
    await tester.tap(find.text('Explore Nearby'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 km'));
    await tester.pumpAndSettle();

    expect(changed, ExploreRadius.district10km);

    // The geo→feed relay refetches with the expanded scope.
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }

    // Both posts blended in ONE feed; nearby card is badged; strip shown.
    expect(find.text('Headline local'), findsOneWidget);
    expect(find.text('Headline nearby'), findsOneWidget);
    expect(find.byType(NearbyBadgeWidget), findsOneWidget);
    expect(find.textContaining('1 post from nearby pins'), findsOneWidget);

    await feedBloc.close();
    await geoBloc.close();
  });
}
