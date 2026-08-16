import 'package:civic_commons/state/ui/ledger_masthead.dart';
import 'package:civic_commons/state/ui/ledger_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LedgerMasthead (Task 7.1)', () {
    testWidgets('renders the nameplate + rule line', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LedgerMasthead(edition: 412, pinCode: '800001')),
        ),
      );

      expect(find.text('THE DAILY LEDGER'), findsOneWidget);
      expect(find.text('EDITION 412 · 800001'), findsOneWidget);
      // The heavy rule line.
      expect(
        find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxHeight == 3),
        findsOneWidget,
      );
    });

    testWidgets('hides edition/pin when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LedgerMasthead()),
        ),
      );

      expect(find.text('THE DAILY LEDGER'), findsOneWidget);
      expect(find.textContaining('EDITION'), findsNothing);
    });

    testWidgets('masthead background is Ledger Green', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LedgerMasthead(pinCode: '800001')),
        ),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('THE DAILY LEDGER'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.color, LedgerTheme.ledgerGreen);
    });

    testWidgets('renders only fixed labels + scoping pin (zero-PII)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LedgerMasthead(edition: 412, pinCode: '800001')),
        ),
      );

      // No phone-shaped or hash-shaped text can appear in the masthead.
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');
      expect(text.contains(RegExp(r'\+91\d{10}')), isFalse);
      expect(text.contains(RegExp(r'[0-9a-f]{64}')), isFalse);
    });
  });
}
