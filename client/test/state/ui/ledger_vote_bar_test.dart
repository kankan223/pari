import 'package:civic_commons/ledger/domain/ledger_vote.dart';
import 'package:civic_commons/state/ui/ledger_theme.dart';
import 'package:civic_commons/state/ui/ledger_vote_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(LedgerVoteDirection myVote, {int score = 6}) => MaterialApp(
        home: Scaffold(
          body: LedgerVoteBar(
            myVote: myVote,
            karmaScore: score,
            onVote: (_) {},
          ),
        ),
      );

  group('LedgerVoteBar (Task 7.5)', () {
    testWidgets('renders the karma-weighted score', (tester) async {
      await tester.pumpWidget(wrap(LedgerVoteDirection.none, score: 6));
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('tapping up fires onVote(up)', (tester) async {
      LedgerVoteDirection? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LedgerVoteBar(
            myVote: LedgerVoteDirection.none,
            karmaScore: 6,
            onVote: (d) => tapped = d,
          ),
        ),
      ));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      expect(tapped, LedgerVoteDirection.up);
    });

    testWidgets('tapping down fires onVote(down)', (tester) async {
      LedgerVoteDirection? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LedgerVoteBar(
            myVote: LedgerVoteDirection.none,
            karmaScore: 6,
            onVote: (d) => tapped = d,
          ),
        ),
      ));
      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      expect(tapped, LedgerVoteDirection.down);
    });

    testWidgets('active upvote renders the up arrow in the active color',
        (tester) async {
      await tester.pumpWidget(wrap(LedgerVoteDirection.up));
      final upIcon =
          tester.widget<Icon>(find.byIcon(Icons.arrow_upward_rounded));
      expect(upIcon.color, LedgerTheme.verifiedEmerald);
      final downIcon =
          tester.widget<Icon>(find.byIcon(Icons.arrow_downward_rounded));
      expect(downIcon.color, LedgerTheme.muted);
    });

    testWidgets('active downvote renders the down arrow in the active color',
        (tester) async {
      await tester.pumpWidget(wrap(LedgerVoteDirection.down));
      final downIcon =
          tester.widget<Icon>(find.byIcon(Icons.arrow_downward_rounded));
      expect(downIcon.color, LedgerTheme.alertRed);
      final upIcon =
          tester.widget<Icon>(find.byIcon(Icons.arrow_upward_rounded));
      expect(upIcon.color, LedgerTheme.muted);
    });

    testWidgets('no active vote renders both arrows muted', (tester) async {
      await tester.pumpWidget(wrap(LedgerVoteDirection.none));
      final upIcon =
          tester.widget<Icon>(find.byIcon(Icons.arrow_upward_rounded));
      final downIcon =
          tester.widget<Icon>(find.byIcon(Icons.arrow_downward_rounded));
      expect(upIcon.color, LedgerTheme.muted);
      expect(downIcon.color, LedgerTheme.muted);
    });

    testWidgets('renders only the score + arrows — no identity strings',
        (tester) async {
      await tester.pumpWidget(wrap(LedgerVoteDirection.none));
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(texts.trim(), '6');
    });
  });
}
