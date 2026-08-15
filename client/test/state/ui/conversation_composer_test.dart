import 'package:civic_commons/state/ui/conversation_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// VERIFY (Task 6.3): the composer is a pure presentational widget — it
/// reports trimmed non-empty text via [onSend], clears after send, disables
/// the action for empty input, and renders zero identifiers/PII.
/// The IconButton hosting the send icon (byIcon matches the Icon itself).
Finder _sendButton() => find.ancestor(
      of: find.byIcon(Icons.send_rounded),
      matching: find.byType(IconButton),
    );

void main() {
  Widget wrap(ValueChanged<String> onSend) => MaterialApp(
        home: Scaffold(
          body: ConversationComposer(onSend: onSend),
        ),
      );

  testWidgets('typing and pressing send reports the trimmed text',
      (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(wrap(sent.add));

    await tester.enterText(find.byType(TextField), '  hello vault  ');
    await tester.pump();
    await tester.tap(_sendButton());
    await tester.pump();

    expect(sent, ['hello vault']);
  });

  testWidgets('the field clears after sending', (tester) async {
    await tester.pumpWidget(wrap((_) {}));

    await tester.enterText(find.byType(TextField), 'clear me');
    await tester.pump();
    await tester.tap(_sendButton());
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('the send action is disabled for empty or whitespace input',
      (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(wrap(sent.add));

    expect(tester.widget<IconButton>(_sendButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<IconButton>(_sendButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'text');
    await tester.pump();
    expect(tester.widget<IconButton>(_sendButton()).onPressed, isNotNull);

    expect(sent, isEmpty);
  });

  testWidgets('pressing the keyboard send action sends the text',
      (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(wrap(sent.add));

    await tester.enterText(find.byType(TextField), 'via keyboard');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(sent, ['via keyboard']);
  });

  testWidgets('renders no PII-shaped text in the composer tree',
      (tester) async {
    await tester.pumpWidget(wrap((_) {}));

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('|');
    expect(RegExp(r'\+91').hasMatch(texts), isFalse);
    expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
  });
}
