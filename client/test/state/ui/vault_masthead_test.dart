import 'package:civic_commons/state/domain/peer_handle.dart';
import 'package:civic_commons/state/ui/vault_masthead.dart';
import 'package:civic_commons/state/ui/vault_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 6.1): VaultMasthead rendering — the classified-document
/// masthead shows the fixed wordmark + stamp + lock, the pseudo-redaction
/// bar, and optional contextMeta / action wiring.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('VaultMasthead - classified aesthetic (Task 6.1)', () {
    testWidgets('renders THE VAULT wordmark, CLASSIFIED stamp, and lock',
        (tester) async {
      await tester.pumpWidget(wrap(const VaultMasthead()));

      expect(find.text('THE VAULT'), findsOneWidget);
      expect(find.text('CLASSIFIED'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });

    testWidgets('renders the pseudo-redaction bar', (tester) async {
      await tester.pumpWidget(wrap(const VaultMasthead()));
      expect(find.textContaining('PRIVATE'), findsOneWidget);
      // The redaction bar is a solid black strip (Container `color:` — the
      // `color:` parameter sets decoration internally, so assert on `color`).
      final bar = tester.widget<Container>(find
          .ancestor(
              of: find.textContaining('PRIVATE'),
              matching: find.byType(Container))
          .first);
      expect(bar.color, VaultTheme.redactionBlack);
    });

    testWidgets('renders the Vault Blue masthead background', (tester) async {
      await tester.pumpWidget(wrap(
          const VaultMasthead())); // The masthead strip uses Container `color:` (not `decoration:`).
      final blueContainer = tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere((c) => c.color == VaultTheme.vaultBlue);
      expect(blueContainer, isNotNull);
    });

    testWidgets('renders contextMeta when provided (already PII-free)',
        (tester) async {
      final handle = formatPeerHandle(
          'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2');
      await tester.pumpWidget(wrap(VaultMasthead(contextMeta: handle)));

      expect(find.text(handle), findsOneWidget);
      // The full blind hash must NOT be rendered anywhere.
      expect(
        find.textContaining(
            'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2'),
        findsNothing,
      );
    });

    testWidgets('omits contextMeta when null', (tester) async {
      await tester.pumpWidget(wrap(const VaultMasthead()));

      expect(find.byType(Text).evaluate().length, 3); // wordmark + stamp + bar
    });

    testWidgets('shows the action button only when onAction is provided',
        (tester) async {
      await tester.pumpWidget(wrap(const VaultMasthead()));

      expect(find.byIcon(Icons.add_rounded), findsNothing);

      await tester.pumpWidget(wrap(VaultMasthead(onAction: () {})));

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('invokes onAction when the new-conversation button is tapped',
        (tester) async {
      var tapped = false;
      await tester
          .pumpWidget(wrap(VaultMasthead(onAction: () => tapped = true)));

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  group('VaultMasthead - SECURITY CHECKPOINT (Task 6.1)', () {
    testWidgets('widget tree contains no PII-shaped text', (tester) async {
      await tester.pumpWidget(wrap(VaultMasthead(
        contextMeta: formatPeerHandle(
            'c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1'),
      )));

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(texts, isNot(contains('+91')));
      expect(texts, isNot(contains('hvs.')));
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      expect(
        RegExp(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')
            .hasMatch(texts),
        isFalse,
      );
    });
  });
}
