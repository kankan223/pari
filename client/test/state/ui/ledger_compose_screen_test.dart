import 'package:civic_commons/ledger/data/in_memory_ledger_draft_sink.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/state/data/local_ledger_compose_bloc.dart';
import 'package:civic_commons/state/domain/ledger_compose_bloc.dart';
import 'package:civic_commons/state/ui/ledger_compose_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(LedgerComposeBloc bloc,
        {String defaultPinCode = '800001', VoidCallback? onSubmitted}) =>
    MaterialApp(
      home: LedgerComposeScreen(
        bloc: bloc,
        defaultPinCode: defaultPinCode,
        onSubmitted: onSubmitted,
      ),
    );

/// Tall viewport so the full compose form (incl. the publish button at the
/// bottom) is on-screen without scrolling.
void _setTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _scrollTo(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump();
}

void main() {
  group('LedgerComposeScreen (Task 7.1)', () {
    testWidgets('renders the form with prefilled pin code', (tester) async {
      _setTallViewport(tester);
      final bloc = LocalLedgerComposeBloc(drafts: InMemoryLedgerDraftSink());
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('New Post'), findsOneWidget);
      expect(find.text('Category *'), findsOneWidget);
      expect(find.text('Pin Code *'), findsOneWidget);
      expect(find.text('Headline *'), findsOneWidget);
      expect(find.text('800001'), findsOneWidget);
      expect(find.text('Publish — send to review'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('selecting a category updates the dropdown', (tester) async {
      final bloc = LocalLedgerComposeBloc(drafts: InMemoryLedgerDraftSink());
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      await tester.tap(find.byType(DropdownButtonFormField<LedgerCategory>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Consumer Watch').last);
      await tester.pumpAndSettle();

      expect(bloc.current.category, LedgerCategory.consumerWatch);
      await bloc.close();
    });

    testWidgets('invalid submission shows the generic error, no persistence',
        (tester) async {
      _setTallViewport(tester);
      final sink = InMemoryLedgerDraftSink();
      var submitted = false;
      final bloc = LocalLedgerComposeBloc(drafts: sink);
      await tester.pumpWidget(_wrap(bloc, onSubmitted: () => submitted = true));
      await tester.pump();

      await _scrollTo(tester, 'Publish — send to review');
      await tester.tap(find.text('Publish — send to review'));
      await tester.pump();
      await tester.pump();

      expect(submitted, isFalse);
      expect(sink.saved, isEmpty);
      expect(
        find.textContaining('add a category, a valid 6-digit pin code'),
        findsOneWidget,
      );
      await bloc.close();
    });

    testWidgets('valid submission persists the draft and fires onSubmitted',
        (tester) async {
      _setTallViewport(tester);
      final sink = InMemoryLedgerDraftSink();
      var submitted = false;
      final bloc = LocalLedgerComposeBloc(drafts: sink);
      await tester.pumpWidget(_wrap(bloc, onSubmitted: () => submitted = true));
      await tester.pump();

      // Select a category.
      await tester.tap(find.byType(DropdownButtonFormField<LedgerCategory>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Civic Infrastructure').last);
      await tester.pumpAndSettle(); // Headline.
      await tester.enterText(
          find.widgetWithText(TextField, 'State the issue plainly'),
          'Boring Road');
      await tester.pump();

      await _scrollTo(tester, 'Publish — send to review');
      await tester.tap(find.text('Publish — send to review'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(submitted, isTrue);
      expect(sink.saved, hasLength(1));
      expect(sink.saved.first.headline, 'Boring Road');
      expect(sink.saved.first.category, LedgerCategory.civicInfrastructure);
      await bloc.close();
    });

    testWidgets('cancel invokes onCancel', (tester) async {
      var cancelled = false;
      final bloc = LocalLedgerComposeBloc(drafts: InMemoryLedgerDraftSink());
      await tester.pumpWidget(MaterialApp(
        home: LedgerComposeScreen(
          bloc: bloc,
          defaultPinCode: '800001',
          onCancel: () => cancelled = true,
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(cancelled, isTrue);
      await bloc.close();
    });

    testWidgets('renders the karma messaging row (Contributor → Peer Review)',
        (tester) async {
      _setTallViewport(tester);
      final bloc = LocalLedgerComposeBloc(drafts: InMemoryLedgerDraftSink());
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(
        find.textContaining('goes to Peer Review Gate before publishing'),
        findsOneWidget,
      );
      await bloc.close();
    });
  });
}
