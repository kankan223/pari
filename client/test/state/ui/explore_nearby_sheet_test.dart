import 'package:civic_commons/geo/domain/explore_radius.dart';
import 'package:civic_commons/geo/domain/geo_place.dart';
import 'package:civic_commons/geo/domain/pin_code.dart';
import 'package:civic_commons/geo/domain/pin_code_resolver.dart';
import 'package:civic_commons/geo/domain/pin_code_store.dart';
import 'package:civic_commons/state/data/local_ledger_geo_bloc.dart';
import 'package:civic_commons/state/domain/ledger_geo_state.dart';
import 'package:civic_commons/state/ui/explore_nearby_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _patna = GeoPlace(
  pinCode: PinCode.forTest('800001'),
  district: 'Patna',
  locality: 'Sadar',
);

class _FakeResolver implements PinCodeResolver {
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
  group('ExploreNearbySheet (Task 7.2)', () {
    testWidgets('renders the scope line and all radius options',
        (tester) async {
      final bloc = LocalLedgerGeoBloc(
        resolver: _FakeResolver(),
        store: _MemStore()..place = _patna,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExploreNearbySheet(
            bloc: bloc,
            state: LedgerGeoState(
              phase: LedgerGeoPhase.resolved,
              place: _patna,
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('EXPLORE NEARBY'), findsOneWidget);
      expect(find.text('Sadar · Patna · 800001'), findsOneWidget);
      expect(find.text('Local only'), findsOneWidget);
      expect(find.text('5 km'), findsOneWidget);
      expect(find.text('10 km'), findsOneWidget);
      expect(find.text('25 km'), findsOneWidget);
      expect(find.text('Use my location'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('selecting a radius updates the bloc and pops with the value',
        (tester) async {
      final bloc = LocalLedgerGeoBloc(
        resolver: _FakeResolver(),
        store: _MemStore()..place = _patna,
      );
      ExploreRadius? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await showModalBottomSheet<ExploreRadius>(
                    context: context,
                    builder: (_) => ExploreNearbySheet(
                      bloc: bloc,
                      state: LedgerGeoState(
                        phase: LedgerGeoPhase.resolved,
                        place: _patna,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 km'));
      await tester.pumpAndSettle();

      expect(popped, ExploreRadius.district10km);
      await bloc.close();
    });

    testWidgets('re-resolve invokes retryResolve on the bloc', (tester) async {
      final resolver = _FakeResolver();
      final bloc = LocalLedgerGeoBloc(
        resolver: resolver,
        store: _MemStore()..place = _patna,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExploreNearbySheet(
            bloc: bloc,
            state: const LedgerGeoState(phase: LedgerGeoPhase.resolved),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Use my location'));
      await tester.pump();
      await tester.pump();

      expect(resolver.calls, greaterThan(0));
      await bloc.close();
    });

    testWidgets('renders NO coordinates — only the coarse scope line',
        (tester) async {
      final bloc = LocalLedgerGeoBloc(
        resolver: _FakeResolver(),
        store: _MemStore()..place = _patna,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExploreNearbySheet(
            bloc: bloc,
            state: LedgerGeoState(
              phase: LedgerGeoPhase.resolved,
              place: _patna,
            ),
          ),
        ),
      ));
      await tester.pump();

      final texts =
          tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '');
      // No latitude/longitude shape, no street address, no hash.
      expect(texts.any((t) => t.contains(RegExp(r'\d{2}\.\d+'))), isFalse);
      expect(texts.any((t) => t.contains('Road')), isFalse);
      expect(texts.any((t) => RegExp(r'[0-9a-f]{64}').hasMatch(t)), isFalse);
      await bloc.close();
    });
  });
}
