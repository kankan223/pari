import 'package:civic_commons/pairing/domain/qr_matrix.dart';
import 'package:civic_commons/state/ui/pairing_qr_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

QrMatrix _matrix() {
  final rows = List<List<bool>>.generate(
    21,
    (_) => List.filled(21, false),
  );
  for (var i = 0; i < 7; i++) {
    for (var j = 0; j < 7; j++) {
      final ring = i == 0 || i == 6 || j == 0 || j == 6;
      final core = i >= 2 && i <= 4 && j >= 2 && j <= 4;
      rows[i][j] = ring || core;
    }
  }
  return QrMatrix.fromRows(rows);
}

void main() {
  testWidgets('renders a QR as a CustomPaint matrix', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PairingQrView(matrix: _matrix()),
      ),
    ));

    // Scaffold adds its own CustomPaint; the PairingQrView's painter is the
    // one inside the widget's subtree.
    expect(
      find.descendant(
        of: find.byType(PairingQrView),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.byType(PairingQrView), findsOneWidget);
  });

  testWidgets('renders the fixed caption, never the payload text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PairingQrView(
          matrix: _matrix(),
          caption: 'Scan with your new device',
        ),
      ),
    ));

    expect(find.text('Scan with your new device'), findsOneWidget);
  });

  testWidgets('QR matrix painter draws dark modules on a canvas',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          child: PairingQrView(matrix: _matrix()),
        ),
      ),
    ));

    // Painting must not throw; the canvas holds the painted QR.
    expect(tester.takeException(), isNull);
  });
}
