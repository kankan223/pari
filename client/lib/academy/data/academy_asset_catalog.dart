import '../domain/academy_module.dart';
import '../domain/module_asset_manifest.dart';

/// Deterministic asset size catalog (Task 9.4 — Offline Module Caching).
///
/// Maps OPAQUE content refs (and their derived transcript refs) to nominal
/// sizes in bytes. The catalog is the single source of truth for a module's
/// offline budget: the manifest is generated from it, so the same module
/// always reports the same size (no randomness, no clock).
///
/// SECURITY CHECKPOINT (Task 9.4): the catalog is keyed ONLY by the opaque
/// non-PII content refs of the bundled seed syllabus — no URLs, no
/// filenames, no identity. The production catalog (Phase-9 content delivery)
/// will be built the same way from the Academy Service's asset metadata.
class AcademyAssetCatalog {
  AcademyAssetCatalog._();

  /// Nominal size table keyed by opaque content ref.
  static const Map<String, int> _sizes = {
    'civics/rights-fundamentals/mod-01': 24 * 1024 * 1024,
    'civics/rights-fundamentals/mod-01/transcript': 140 * 1024,
    'civics/reporting-basics/mod-02': 30 * 1024 * 1024,
    'civics/reporting-basics/mod-02/transcript': 190 * 1024,
    'tech/privacy-phone/mod-03': 18 * 1024 * 1024,
  };

  /// The deterministic manifest for [module] using the bundled sizes.
  static ModuleAssetManifest manifestFor(AcademyModule module) =>
      ModuleAssetManifest.generateFor(module, sizes: _sizes);

  /// The deterministic manifest for EVERY module in [syllabus] (keyed by
  /// module id — zero identity).
  static Map<String, ModuleAssetManifest> manifestsFor(
          AcademySyllabus syllabus) =>
      {
        for (final m in syllabus.modules) m.moduleId: manifestFor(m),
      };
}
