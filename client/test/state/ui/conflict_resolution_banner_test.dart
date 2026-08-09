import 'package:civic_commons/repository/domain/conflict_resolution.dart';
import 'package:civic_commons/state/ui/conflict_resolution_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 5.5): the [ConflictResolutionBanner] renders each decision
/// with fixed, non-PII labels and never exposes entity ids, hashes, or
/// payload contents.
void main() {
  MutationVersion version({String author = 'hash-a'}) => MutationVersion(
        entityId: 'msg-1',
        timestamp: DateTime(2026, 8, 4, 12),
        serverAcknowledged: true,
        authorHash: author,
      );

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: child,
          ),
        ),
      );

  testWidgets('renders "Local edit kept" for applyLocal', (tester) async {
    final local = version(author: 'hash-local');
    await tester.pumpWidget(wrap(ConflictResolutionBanner(
      resolution: ConflictResolution(ConflictDecision.applyLocal, local),
    )));

    expect(find.text('Local edit kept'), findsOneWidget);
  });

  testWidgets('renders "Server version applied" for applyRemote',
      (tester) async {
    final remote = version(author: 'hash-remote');
    await tester.pumpWidget(wrap(ConflictResolutionBanner(
      resolution: ConflictResolution(ConflictDecision.applyRemote, remote),
    )));

    expect(find.text('Server version applied'), findsOneWidget);
  });

  testWidgets('renders "Changes merged" + merged value for merge',
      (tester) async {
    final winner = version(author: 'hash-winner');
    await tester.pumpWidget(wrap(ConflictResolutionBanner(
      resolution: ConflictResolution(
        ConflictDecision.merge,
        winner,
        mergedValue: 42,
      ),
    )));

    expect(find.text('Changes merged'), findsOneWidget);
    expect(find.text('Merged value: 42'), findsOneWidget);
  });

  testWidgets('merge without a value omits the value line', (tester) async {
    final winner = version(author: 'hash-winner');
    await tester.pumpWidget(wrap(ConflictResolutionBanner(
      resolution: ConflictResolution(ConflictDecision.merge, winner),
    )));

    expect(find.text('Changes merged'), findsOneWidget);
    expect(find.textContaining('Merged value'), findsNothing);
  });

  testWidgets('SECURITY CHECKPOINT - never renders ids, hashes, or payloads',
      (tester) async {
    final remote = version(author: 'hash-remote');
    await tester.pumpWidget(wrap(ConflictResolutionBanner(
      resolution: ConflictResolution(ConflictDecision.applyRemote, remote),
    )));

    // Fixed labels only — no entity id, blind hash, or timestamp leaks.
    expect(find.textContaining('msg-1'), findsNothing);
    expect(find.textContaining('hash-'), findsNothing);
    expect(find.textContaining('2026'), findsNothing);
    expect(find.text('msg-1'), findsNothing);
  });

  testWidgets('invokes onTap when tapped', (tester) async {
    var tapped = 0;
    final remote = version(author: 'hash-remote');
    await tester.pumpWidget(wrap(ConflictResolutionBanner(
      resolution: ConflictResolution(ConflictDecision.applyRemote, remote),
      onTap: () => tapped++,
    )));

    await tester.tap(find.text('Server version applied'));
    await tester.pump();

    expect(tapped, 1);
  });
}
