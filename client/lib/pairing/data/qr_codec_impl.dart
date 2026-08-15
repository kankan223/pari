import 'package:qr/qr.dart';

import '../domain/qr_matrix.dart';

/// [QrEncoder] backed by the pure-Dart `qr` package (data layer, Task 6.5).
///
/// Maps the payload string bytes to QR modules at medium error correction
/// (~15% recoverable) — a good balance for on-screen pairing codes that may
/// be photographed at an angle.
///
/// SECURITY CHECKPOINT (Task 6.5): this is a pure byte→module encoder. It
/// never inspects, logs, or interprets the payload content — a pairing code
/// (which carries public keys) is opaque bytes to this class, so no PII or
/// key material can leak through it.
class QrCodecEncoder implements QrEncoder {
  final QrErrorCorrectLevel errorCorrectLevel;

  const QrCodecEncoder({
    this.errorCorrectLevel = QrErrorCorrectLevel.medium,
  });

  @override
  QrMatrix encode(String data) {
    final code = QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: errorCorrectLevel,
    );
    final image = QrImage(code);
    final count = code.moduleCount;
    final rows = <List<bool>>[];
    for (var y = 0; y < count; y++) {
      final row = <bool>[];
      for (var x = 0; x < count; x++) {
        row.add(image.isDark(y, x));
      }
      rows.add(row);
    }
    return QrMatrix.fromRows(rows);
  }
}
