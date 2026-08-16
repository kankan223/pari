import 'package:civic_commons/state/ui/war_case_severity_band.dart';
import 'package:civic_commons/state/ui/war_room_masthead.dart';
import 'package:civic_commons/state/ui/war_room_theme.dart';
import 'package:civic_commons/war_room/domain/case_severity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WarRoomMasthead (Task 8.1)', () {
    testWidgets('renders the dossier stamp bar + secure-channel subtitle',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WarRoomMasthead()),
        ),
      );

      expect(find.text('▌WAR ROOM▐'), findsOneWidget);
      expect(find.text('CIVIC COMMONS OSINT UNIT — SECURE CHANNEL'),
          findsOneWidget);
      // The charcoal stamp rule.
      expect(
        find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxHeight == 3),
        findsOneWidget,
      );
    });

    testWidgets('renders section label, case stamp, and severity band',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WarRoomMasthead(
              label: 'Your Cases',
              caseNumber: 'CC-0047',
              severity: CaseSeverity.high,
            ),
          ),
        ),
      );

      expect(find.text('YOUR CASES'), findsOneWidget);
      expect(find.text('CASE #CC-0047'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget); // compact severity band
      expect(find.byType(WarCaseSeverityBand), findsOneWidget);
    });

    testWidgets('masthead background is dossier ink (charcoal)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WarRoomMasthead()),
        ),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('▌WAR ROOM▐'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.color, WarRoomTheme.dossierInk);
    });

    testWidgets('hides optional stamp/severity when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WarRoomMasthead()),
        ),
      );
      expect(find.textContaining('CASE #'), findsNothing);
      expect(find.byType(WarCaseSeverityBand), findsNothing);
    });

    testWidgets('renders only fixed labels + public stamp (zero-PII)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WarRoomMasthead(
              label: 'Your Cases',
              caseNumber: 'CC-0047',
              severity: CaseSeverity.critical,
            ),
          ),
        ),
      );

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      // No 64-hex blind hashes, no phones, no Vault tokens, no handles.
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      expect(texts, isNot(contains('+91')));
      expect(texts, isNot(contains('hvs.')));
      expect(texts, isNot(contains('@')));
    });
  });
}
