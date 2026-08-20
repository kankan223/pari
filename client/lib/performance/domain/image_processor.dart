import 'dart:typed_data';

import 'image_compression_config.dart';

/// Port for image compression and resizing operations.
///
/// Implementations provide platform-specific image processing (Dart native
/// or platform channels). The port itself contains no identity/PII logic.
abstract class ImageProcessor {
  /// Compresses and resizes image data according to the config.
  ///
  /// Returns compressed image bytes, or null on failure.
  Future<Uint8List?> compress(Uint8List input, {ImageCompressionConfig config});

  /// Returns the estimated output size in bytes before compression.
  Future<int> estimateSize(Uint8List input);

  /// Generates a thumbnail (fast, low-quality resize).
  Future<Uint8List?> thumbnail(Uint8List input, {int maxDimension = 200});
}
