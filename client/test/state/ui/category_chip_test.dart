import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/state/ui/category_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CategoryChip (Task 7.1)', () {
    testWidgets('renders the category label for every category',
        (tester) async {
      for (final category in LedgerCategory.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: CategoryChip(category: category)),
          ),
        );
        expect(find.text(category.label), findsOneWidget);
      }
    });

    testWidgets('tapping invokes onTap (filter chips)', (tester) async {
      LedgerCategory? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategoryChip(
              category: LedgerCategory.breakingLocal,
              onTap: () => tapped = LedgerCategory.breakingLocal,
            ),
          ),
        ),
      );
      await tester.tap(find.text('#BREAKING'));
      await tester.pump();
      expect(tapped, LedgerCategory.breakingLocal);
    });

    testWidgets('static chip (no onTap) renders but is not tappable',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CategoryChip(category: LedgerCategory.civicInfrastructure),
          ),
        ),
      );
      expect(find.text('#CIVIC INFRA'), findsOneWidget);
      // No InkWell wrapper means no tap target.
      expect(
        find.ancestor(
          of: find.text('#CIVIC INFRA'),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });
  });
}
