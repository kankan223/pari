import 'package:flutter/material.dart';

import '../../pairing/domain/qr_matrix.dart';
import 'vault_theme.dart';

/// Renders a [QrMatrix] as pixels (Task 6.5 device pairing).
///
/// The pairing payload is displayed ONLY as a QR code — the raw payload text
/// (which carries the public key material) is never rendered or exposed to
/// the widget tree as a string.
///
/// SECURITY CHECKPOINT (Task 6.5): this widget renders a matrix of dark
/// modules. No identifiers, no key material, no payload text appear in the
/// tree; the only strings are fixed labels.
class PairingQrView extends StatelessWidget {
  final QrMatrix matrix;

  /// Fixed, non-sensitive label under the QR (e.g. "Scan with your new
  /// device").
  final String? caption;

  const PairingQrView({super.key, required this.matrix, this.caption});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: VaultTheme.vaultBlue, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: CustomPaint(
            size: const Size(200, 200),
            painter: _QrPainter(matrix),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 10),
          Text(
            caption!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Paints dark QR modules on a white canvas with a quiet-zone margin.
class _QrPainter extends CustomPainter {
  final QrMatrix matrix;

  _QrPainter(this.matrix);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF000000);
    final count = matrix.moduleCount;
    if (count == 0) {
      return;
    }
    // 5-module quiet zone on each side.
    const quiet = 4.0;
    final module =
        (size.width - quiet * 2) / count; // square: use width for both axes
    const origin = quiet;
    for (var y = 0; y < count; y++) {
      for (var x = 0; x < count; x++) {
        if (matrix.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(
              origin + x * module,
              origin + y * module,
              module + 0.5, // +0.5 avoids hairline gaps between modules
              module + 0.5,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.matrix != matrix;
}
