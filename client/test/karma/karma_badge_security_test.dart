import 'dart:io';

import 'package:civic_commons/karma/domain/karma_badge.dart';
import 'package:civic_commons/karma/ui/karma_badge_indicator.dart';
import 'package:civic_commons/karma/ui/karma_tier_chip.dart';
import 'package:civic_commons/state/domain/karma_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 10.3 SECURITY CHECKPOINT — Karma Badge UI', () {
    test('badge value object carries only public integers and fixed labels', () {
      for (final tier in KarmaTier.values) {
        final badge = KarmaBadge.forTier(tier);
        // No hex-hash-like strings
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(badge.label), isFalse);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(badge.description), isFalse);
        // No phone-like strings
        expect(RegExp(r'\+\d{10,}').hasMatch(badge.description), isFalse);
        // No email strings
        expect(badge.description.contains('@'), isFalse);
      }
    });

    test('karma badge UI files have zero networking imports', () {
      final files = [
        'lib/karma/domain/karma_badge.dart',
        'lib/karma/ui/karma_tier_chip.dart',
        'lib/karma/ui/karma_badge_indicator.dart',
      ];
      for (final path in files) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();
        // Only check non-comment lines
        final codeLines = source.split('\n').where((line) {
          final trimmed = line.trim();
          return !trimmed.startsWith('//') && !trimmed.startsWith('///');
        }).join('\n');
        expect(codeLines.contains('dart:io'), isFalse,
            reason: '$path must not import dart:io');
        expect(codeLines.contains('package:http'), isFalse,
            reason: '$path must not import package:http');
        expect(codeLines.contains('package:web_socket_channel'), isFalse,
            reason: '$path must not import package:web_socket_channel');
      }
    });

    test('no print or debugPrint in karma badge files', () {
      final files = [
        'lib/karma/domain/karma_badge.dart',
        'lib/karma/ui/karma_tier_chip.dart',
        'lib/karma/ui/karma_badge_indicator.dart',
      ];
      for (final path in files) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();
        // Only check non-comment lines
        final codeLines = source.split('\n').where((line) {
          final trimmed = line.trim();
          return !trimmed.startsWith('//') && !trimmed.startsWith('///');
        }).join('\n');
        expect(codeLines.contains('print('), isFalse,
            reason: '$path must not contain print()');
        expect(codeLines.contains('debugPrint('), isFalse,
            reason: '$path must not contain debugPrint()');
      }
    });

    testWidgets('KarmaTierChip renders zero-PII widget tree', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KarmaTierChip(balance: 500)),
      ));
      // Render all text widgets and scan for PII
      final textWidgets = find.byType(Text);
      for (final element in textWidgets.evaluate()) {
        final widget = element.widget as Text;
        final data = widget.data ?? '';
        // No 64-hex blind hash
        expect(RegExp(r'[0-9a-f]{64}').hasMatch(data), isFalse,
            reason: 'PII found in chip: $data');
        // No phone pattern
        expect(RegExp(r'\+\d{10,}').hasMatch(data), isFalse,
            reason: 'Phone found in chip: $data');
        // No email
        expect(RegExp(r'\S+@\S+').hasMatch(data), isFalse,
            reason: 'Email found in chip: $data');
      }
    });

    testWidgets('KarmaBadgeIndicator renders zero-PII widget tree', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KarmaBadgeIndicator(balance: 500)),
      ));
      final textWidgets = find.byType(Text);
      for (final element in textWidgets.evaluate()) {
        final widget = element.widget as Text;
        final data = widget.data ?? '';
        expect(RegExp(r'[0-9a-f]{64}').hasMatch(data), isFalse,
            reason: 'PII found in indicator: $data');
        expect(RegExp(r'\+\d{10,}').hasMatch(data), isFalse,
            reason: 'Phone found in indicator: $data');
      }
    });
  });
}
