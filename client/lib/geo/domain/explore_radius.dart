/// The Explore Nearby radius scope (DESIGN.md §5.2, Task 7.2).
///
/// A radius is a COARSE, user-chosen civic scope — it never encodes or
/// requires device coordinates. `none` = the default local-only feed
/// (exact pin code). Larger radii broaden the feed to neighbouring
/// pins/constituencies (the dynamic-radius skill governs the fallback
/// behaviour when a radius yields an empty feed).
enum ExploreRadius {
  /// Local-only (default): exact pin-code scope.
  none,

  /// ~5 km — neighbouring locality pins.
  nearby5km,

  /// ~10 km — the district / Assembly constituency.
  district10km,

  /// ~25 km — the wider civic area.
  metro25km;

  /// The human label for the radius chip/sheet.
  String get label => switch (this) {
        ExploreRadius.none => 'Local only',
        ExploreRadius.nearby5km => '5 km',
        ExploreRadius.district10km => '10 km',
        ExploreRadius.metro25km => '25 km',
      };

  /// The scope hint shown under the label.
  String get detail => switch (this) {
        ExploreRadius.none => 'Your pin code only',
        ExploreRadius.nearby5km => 'Neighbouring pins',
        ExploreRadius.district10km => 'Your district',
        ExploreRadius.metro25km => 'The wider area',
      };

  bool get isExpanded => this != ExploreRadius.none;
}
