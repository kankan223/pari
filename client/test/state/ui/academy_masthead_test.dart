import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/ui/academy_masthead.dart';
import 'package:civic_commons/state/ui/academy_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records FLAG_SECURE enable/disable calls (mirrors the War Room
/// checkpoint convention).
class _RecordingFlagService implements SecureFlagService {
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> enableSecureFlag() async {
    enableCalls++;
  }

  @override
  Future<void> disableSecureFlag() async {
    disableCalls++;
  }

  @override
  Future<bool> isSecureFlagSupported() async => true;
}

void main() {
  group('AcademyMasthead (Phase 9 foundation)', () {
    testWidgets('renders the textbook stamp bar + open-education subtitle',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AcademyMasthead()),
        ),
      );

      expect(find.text('❧ THE ACADEMY'), findsOneWidget);
      expect(find.text('CIVIC COMMONS OPEN EDUCATION — LEARN WITHOUT LIMITS'),
          findsOneWidget);
      // The emerald chapter rule.
      expect(
        find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxHeight == 3),
        findsOneWidget,
      );
    });

    testWidgets('renders section label and module count when provided',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AcademyMasthead(label: 'Browse Curriculum', moduleCount: 3),
          ),
        ),
      );

      expect(find.text('BROWSE CURRICULUM'), findsOneWidget);
      expect(find.text('3 modules'), findsOneWidget);
    });

    testWidgets('masthead background is Academy ink (textbook register)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AcademyMasthead()),
        ),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('❧ THE ACADEMY'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.color, AcademyTheme.ink);
    });

    testWidgets('hides label/module count when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AcademyMasthead()),
        ),
      );

      expect(find.textContaining('modules'), findsNothing);
      expect(find.text('BROWSE CURRICULUM'), findsNothing);
    });

    testWidgets('SECURITY: enables FLAG_SECURE when mounted', (tester) async {
      final flag = _RecordingFlagService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AcademyMasthead(secureFlagService: flag),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(flag.enableCalls, greaterThanOrEqualTo(1),
          reason: 'the Academy masthead must enable FLAG_SECURE');
    });
  });
}
