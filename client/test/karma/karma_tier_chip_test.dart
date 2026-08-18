import 'package:civic_commons/karma/ui/karma_badge_indicator.dart';
import 'package:civic_commons/karma/ui/karma_tier_chip.dart';
import 'package:civic_commons/state/domain/karma_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KarmaTierChip', () {
    testWidgets('renders nothing when tier and balance are null', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KarmaTierChip())));
      expect(find.byType(KarmaTierChip), findsOneWidget);
      // Nothing rendered inside the chip (SizedBox.shrink)
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('renders citizen tier for balance 0', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KarmaTierChip(balance: 0))));
      expect(find.text('CITIZEN'), findsOneWidget);
    });

    testWidgets('renders contributor tier for balance 75', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KarmaTierChip(balance: 75))));
      expect(find.text('CONTRIBUTOR'), findsOneWidget);
    });

    testWidgets('renders validator tier for balance 120', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KarmaTierChip(balance: 120))));
      expect(find.text('VALIDATOR'), findsOneWidget);
    });

    testWidgets('renders analyst tier for balance 300', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KarmaTierChip(balance: 300))));
      expect(find.text('ANALYST'), findsOneWidget);
    });

    testWidgets('renders council tier for balance 500', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KarmaTierChip(balance: 500))));
      expect(find.text('COUNCIL'), findsOneWidget);
    });

    testWidgets('uses explicit tier over balance', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KarmaTierChip(tier: KarmaTier.analyst, balance: 10)),
      ));
      // Explicit tier wins: Analyst (not Citizen from balance=10)
      expect(find.text('ANALYST'), findsOneWidget);
      expect(find.text('CITIZEN'), findsNothing);
    });

    testWidgets('compact mode renders smaller text', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KarmaTierChip(balance: 200, compact: true)),
      ));
      final text = tester.widget<Text>(find.text('ANALYST'));
      expect(text.style!.fontSize, 9.0);
    });

    testWidgets('non-compact mode renders standard text', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KarmaTierChip(balance: 200)),
      ));
      final text = tester.widget<Text>(find.text('ANALYST'));
      expect(text.style!.fontSize, 10.0);
    });
  });

  group('KarmaBadgeIndicator', () {
    testWidgets('renders nothing when tier and balance are null', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KarmaBadgeIndicator())));
      expect(find.byType(KarmaBadgeIndicator), findsOneWidget);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('renders tier label for balance', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KarmaBadgeIndicator(balance: 250))));
      expect(find.text('ANALYST'), findsOneWidget);
    });

    testWidgets('renders balance number when provided', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: KarmaBadgeIndicator(balance: 250))));
      expect(find.text('250'), findsOneWidget);
    });

    testWidgets('does not render balance when not provided', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KarmaBadgeIndicator(tier: KarmaTier.council)),
      ));
      expect(find.text('COUNCIL'), findsOneWidget);
      // No balance number rendered
      expect(find.text('500'), findsNothing);
    });

    testWidgets('uses explicit tier over balance', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KarmaBadgeIndicator(tier: KarmaTier.council, balance: 10)),
      ));
      expect(find.text('COUNCIL'), findsOneWidget);
      expect(find.text('CITIZEN'), findsNothing);
    });
  });

  group('KarmaTierChip — SECURITY CHECKPOINT (zero-PII)', () {
    testWidgets('no 64-hex hash, no phone, no blind handle in widget tree', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KarmaTierChip(balance: 500)),
      ));

      final text = find.byType(Text);
      for (final element in text.evaluate()) {
        final widget = element.widget as Text;
        final data = widget.data ?? '';
        // No 64-hex string (blind hash)
        expect(RegExp(r'[0-9a-f]{64}').hasMatch(data), isFalse,
            reason: 'Found 64-hex hash in chip text: $data');
        // No phone-like pattern
        expect(RegExp(r'\+\d{10,}').hasMatch(data), isFalse,
            reason: 'Found phone pattern in chip text: $data');
        // No email pattern
        expect(RegExp(r'\S+@\S+').hasMatch(data), isFalse,
            reason: 'Found email in chip text: $data');
      }
    });
  });
}
