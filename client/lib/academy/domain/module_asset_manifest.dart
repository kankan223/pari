import 'academy_module.dart';

/// The kind of a module asset that can be cached for offline use
/// (Task 9.4 — Offline Module Caching).
///
/// The Academy caches PUBLIC course content only. [video] is the module's
/// lecture asset (the opaque [AcademyModule.contentRef]); [transcript] is
/// the derived text asset. ZERO identity is attached to either kind — an
/// asset's only key is the module's UUID v4 id plus its opaque non-PII ref.
enum ModuleAssetKind {
  video('video'),
  transcript('transcript');

  /// Stable wire name (persisted in the cache status rows / manifests).
  final String wireName;

  const ModuleAssetKind(this.wireName);

  static ModuleAssetKind fromWireName(String raw) => values.firstWhere(
        (k) => k.wireName == raw,
        orElse: () => throw ArgumentError('unknown module asset kind: $raw'),
      );
}

/// A single module asset in an offline manifest.
///
/// SECURITY CHECKPOINT (Task 9.4): [ref] is the module's OPAQUE non-PII
/// content reference (or a derived opaque ref for transcripts) — never a
/// raw URL, never a filename that could leak identity. [sizeBytes] is the
/// deterministic nominal size used for the storage warning.
class ModuleAsset {
  final ModuleAssetKind kind;
  final String ref;
  final int sizeBytes;

  const ModuleAsset({
    required this.kind,
    required this.ref,
    required this.sizeBytes,
  });

  @override
  bool operator ==(Object other) =>
      other is ModuleAsset &&
      other.kind == kind &&
      other.ref == ref &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(kind, ref, sizeBytes);
}

/// The deterministic offline manifest for a module: the list of assets with
/// their sizes (MASTER_PLAN §9.4 — "module manifest generation (list of
/// assets with sizes)").
///
/// Generated from the module + a size table; identical inputs ALWAYS
/// produce the identical manifest (no randomness, no clock) so a module's
/// offline budget is a stable, testable number.
class ModuleAssetManifest {
  /// The module's validated UUID v4 id (cache key — zero identity).
  final String moduleId;

  /// The module's public title (rendered in the download-for-offline UI).
  final String moduleTitle;

  /// The deterministic asset list (video + optional transcript).
  final List<ModuleAsset> assets;

  const ModuleAssetManifest({
    required this.moduleId,
    required this.moduleTitle,
    required this.assets,
  });

  /// Total offline budget for this module (sum of all asset sizes).
  int get totalSizeBytes => assets.fold(0, (sum, a) => sum + a.sizeBytes);

  bool get isEmpty => assets.isEmpty;

  /// Builds the deterministic manifest for [module].
  ///
  /// [sizes] maps an opaque content ref → nominal size in bytes (the
  /// bundled catalog in the data layer). The VIDEO asset always uses the
  /// module's opaque [AcademyModule.contentRef]; the TRANSCRIPT asset uses
  /// the derived opaque ref `$contentRef/transcript` and is included only
  /// when [sizes] provides it (a module with no transcript has no transcript
  /// asset — the UI then never offers one).
  static ModuleAssetManifest generateFor(
    AcademyModule module, {
    required Map<String, int> sizes,
    int fallbackVideoSize = 64 * 1024 * 1024,
    int fallbackTranscriptSize = 256 * 1024,
  }) {
    final assets = <ModuleAsset>[
      ModuleAsset(
        kind: ModuleAssetKind.video,
        ref: module.contentRef,
        sizeBytes: sizes[module.contentRef] ?? fallbackVideoSize,
      ),
    ];
    final transcriptRef = '${module.contentRef}/transcript';
    if (sizes.containsKey(transcriptRef)) {
      assets.add(ModuleAsset(
        kind: ModuleAssetKind.transcript,
        ref: transcriptRef,
        sizeBytes: sizes[transcriptRef] ?? fallbackTranscriptSize,
      ));
    }
    return ModuleAssetManifest(
      moduleId: module.moduleId,
      moduleTitle: module.title,
      assets: assets,
    );
  }
}
