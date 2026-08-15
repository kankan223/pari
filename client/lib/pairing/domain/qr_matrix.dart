/// A QR code as a grid of dark/light modules (Task 6.5).
///
/// A pure value object so the domain can reason about the QR without
/// depending on any rendering/scanner package. [isDark] follows the QR
/// convention `isDark(row, col)` (row-major), matching the `qr` package's
/// `QrImage.isDark`.
class QrMatrix {
  final int moduleCount;
  final List<List<bool>> _modules;

  const QrMatrix._(this.moduleCount, this._modules);

  /// Builds a matrix from a row-major list of rows of dark-module booleans.
  ///
  /// Throws [ArgumentError] when the grid is not square or is empty.
  factory QrMatrix.fromRows(List<List<bool>> rows) {
    if (rows.isEmpty) {
      throw ArgumentError('QR matrix must not be empty');
    }
    final count = rows.length;
    for (final row in rows) {
      if (row.length != count) {
        throw ArgumentError('QR matrix must be square');
      }
    }
    return QrMatrix._(count, rows);
  }

  /// Whether the module at (row, col) is dark.
  bool isDark(int row, int col) => _modules[row][col];
}

/// Port for encoding a payload string into a renderable [QrMatrix].
///
/// The production implementation wraps the pure-Dart `qr` package (data
/// layer); domain/tests use in-memory fakes. The encoder NEVER sees the
/// payload content — it only maps bytes to modules, so no PII can leak
/// through this boundary.
abstract class QrEncoder {
  /// Encodes [data] into a QR matrix.
  QrMatrix encode(String data);
}

/// Port for capturing QR content from the physical world.
///
/// The production implementation uses the device camera; tests inject a
/// scripted scanner. The port returns the raw decoded STRING — the caller
/// (pairing service) is the only place that interprets it, so scanning can
/// never bypass payload validation.
abstract class QrScanner {
  /// Captures one QR frame and returns the decoded payload string, or null
  /// when nothing was captured (cancel / no code found).
  Future<String?> scan();
}
