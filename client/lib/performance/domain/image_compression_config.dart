/// Configuration for image compression and resizing (Task 12.1).
///
/// Defines quality, dimensions, and format parameters for image processing.
/// All values are pure and deterministic — no identity, no PII.
class ImageCompressionConfig {
  /// JPEG/WebP quality factor (0-100, lower = more compression).
  final int quality;

  /// Maximum width in pixels (0 = no resize).
  final int maxWidth;

  /// Maximum height in pixels (0 = no resize).
  final int maxHeight;

  /// Whether to maintain aspect ratio when resizing.
  final bool maintainAspectRatio;

  /// Whether to strip EXIF data (recommended for privacy).
  final bool stripExif;

  const ImageCompressionConfig({
    this.quality = 85,
    this.maxWidth = 1920,
    this.maxHeight = 1080,
    this.maintainAspectRatio = true,
    this.stripExif = true,
  });

  /// Conservative config for low-end devices / slow connections.
  const ImageCompressionConfig.conservative()
      : quality = 70,
        maxWidth = 1280,
        maxHeight = 720,
        maintainAspectRatio = true,
        stripExif = true;

  /// High quality config for War Room evidence uploads.
  const ImageCompressionConfig.evidence()
      : quality = 95,
        maxWidth = 2560,
        maxHeight = 1440,
        maintainAspectRatio = true,
        stripExif = true; // Strip EXIF even for evidence (privacy)

  /// Creates a config with target file size in bytes.
  factory ImageCompressionConfig.forTargetSize(int targetBytes) {
    // Map target size to quality factor (heuristic)
    if (targetBytes < 50 * 1024) {
      return const ImageCompressionConfig(
          quality: 50, maxWidth: 800, maxHeight: 600);
    } else if (targetBytes < 200 * 1024) {
      return const ImageCompressionConfig(
          quality: 70, maxWidth: 1280, maxHeight: 720);
    } else if (targetBytes < 500 * 1024) {
      return const ImageCompressionConfig(
          quality: 85, maxWidth: 1920, maxHeight: 1080);
    } else {
      return const ImageCompressionConfig(
          quality: 95, maxWidth: 2560, maxHeight: 1440);
    }
  }
}
