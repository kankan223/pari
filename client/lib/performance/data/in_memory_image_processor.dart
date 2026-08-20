import 'dart:typed_data';

import '../domain/image_compression_config.dart';
import '../domain/image_processor.dart';

/// In-memory implementation of [ImageProcessor] for tests (Task 12.1).
///
/// Simulates image compression by truncating to a size proportional to the
/// quality factor, without actual image processing dependencies.
class InMemoryImageProcessor implements ImageProcessor {
  /// Simulated compression ratio per quality level (quality / 100).
  static double _compressionRatio(int quality) => quality / 100.0;

  @override
  Future<Uint8List?> compress(
    Uint8List input, {
    ImageCompressionConfig config = const ImageCompressionConfig(),
  }) async {
    if (input.isEmpty) return null;

    // Simulate compression: output ≈ input * (quality/100)
    final ratio = _compressionRatio(config.quality);
    final targetSize = (input.length * ratio).round();

    // Simulate resize by truncating proportionally
    if (config.maxWidth > 0 || config.maxHeight > 0) {
      // Further reduce based on dimension constraints
      const dimensionFactor = 0.8; // Simulate 20% reduction from resize
      final finalSize = (targetSize * dimensionFactor).round();
      if (finalSize >= input.length) return Uint8List.fromList(input);
      return Uint8List.sublistView(input, 0, finalSize);
    }

    if (targetSize >= input.length) return Uint8List.fromList(input);
    return Uint8List.sublistView(input, 0, targetSize);
  }

  @override
  Future<int> estimateSize(Uint8List input) async {
    // Estimate compressed size at default quality
    return (input.length * 0.85).round();
  }

  @override
  Future<Uint8List?> thumbnail(
    Uint8List input, {
    int maxDimension = 200,
  }) async {
    if (input.isEmpty) return null;

    // Simulate thumbnail: ~10% of original size
    final thumbSize = (input.length * 0.1).round();
    if (thumbSize >= input.length) return Uint8List.fromList(input);
    return Uint8List.sublistView(input, 0, thumbSize);
  }
}
