import 'package:civic_commons/geo/domain/explore_radius.dart';
import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/state/data/local_ledger_feed_bloc.dart';
import 'package:civic_commons/state/domain/ledger_feed_bloc.dart';
import 'package:civic_commons/state/ui/ledger_feed_screen.dart';
import 'package:civic_commons/state/ui/nearby_badge_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerPost _post({
  required String id,
  String pinCode = '800001',
  String? district = 'Patna',
  LedgerCategory category = LedgerCategory.civicInfrastructure,
  required DateTime createdAt,
}) =>
    LedgerPost(
      id: id,
      category: category,
      pinCode: pinCode,
      district: district,
      headline: 'Headline $id',
      body: 'Body $id',
      authorHandle: 'handle_$id',
      createdAt: createdAt,
    );

Widget _wrap(LedgerFeedBloc bloc, {String pinCode = '800001'}) => MaterialApp(
      home: LedgerFeedScreen(bloc: bloc, pinCode: pinCode),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

void main() {
  group('Dynamic radius feed UI (Task 7.3)', () {
    testWidgets('NearbyBadge renders on nearby posts only', (tester) async {
      final now = DateTime.now();
      final bloc = LocalLedgerFeedBloc(
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
      await tester.pumpWidget(_wrap(bloc));
      await _settle(tester);

      // Local-only: no badge.
      expect(find.byType(NearbyBadgeWidget), findsNothing);

      // Expand → nearby post gets the badge; local does not.
      await bloc.setRadius(ExploreRadius.district10km);
      await _settle(tester);

      expect(find.byType(NearbyBadgeWidget), findsOneWidget);
      expect(find.text('NEARBY'), findsOneWidget);
      // The nearby post card shows the badge next to its chip.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Headline nearby'),
            matching: find.byType(Card),
          ),
          matching: find.byType(NearbyBadgeWidget),
        ),
        findsOneWidget,
      );
      await bloc.close();
    });

    testWidgets('nearby strip announces the expanded feed', (tester) async {
      final now = DateTime.now();
      final bloc = LocalLedgerFeedBloc(
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
      await tester.pumpWidget(_wrap(bloc));
      await _settle(tester);

      expect(find.textContaining('nearby pins'), findsNothing);

      await bloc.setRadius(ExploreRadius.district10km);
      await _settle(tester);

      expect(find.textContaining('1 post from nearby pins'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('blended feed shows both local and nearby cards',
        (tester) async {
      final now = DateTime.now();
      final bloc = LocalLedgerFeedBloc(
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
      await tester.pumpWidget(_wrap(bloc));
      await _settle(tester);

      await bloc.setRadius(ExploreRadius.nearby5km);
      await _settle(tester);

      expect(find.text('Headline local'), findsOneWidget);
      expect(find.text('Headline nearby'), findsOneWidget);
      // Single blended feed — both cards in the same list.
      expect(find.byType(Card), findsNWidgets(2));
      await bloc.close();
    });

    testWidgets('dense local feed does not expand (badge stays absent)',
        (tester) async {
      final now = DateTime.now();
      final bloc = LocalLedgerFeedBloc(
        repository: InMemoryLedgerFeedRepository(
          seed: [
            for (var i = 0; i < 5; i++)
              _post(id: 'local$i', createdAt: now.subtract(Duration(days: i))),
            _post(
                id: 'nearby',
                pinCode: '800002',
                district: 'Patna',
                createdAt: now),
          ],
        ),
      );
      await tester.pumpWidget(_wrap(bloc));
      await _settle(tester);

      await bloc.setRadius(ExploreRadius.metro25km);
      await _settle(tester);

      expect(find.byType(NearbyBadgeWidget), findsNothing);
      expect(find.textContaining('nearby pins'), findsNothing);
      await bloc.close();
    });
  });
}
