import 'pin_code.dart';

/// A coarse geographic place resolved from the device location.
///
/// SECURITY CHECKPOINT (Task 7.2): [GeoPlace] carries ONLY the public pin
/// code and coarse civic names (district / locality). It is the ONLY
/// location-bearing value that crosses the data-layer boundary — raw
/// coordinates, addresses, and street-level placemarks never leave the
/// data layer and are never stored or logged.
class GeoPlace {
  final PinCode pinCode;

  /// Coarse district / Assembly-constituency name (public civic info).
  final String? district;

  /// Locality or sub-locality name (public civic info, coarse only).
  final String? locality;

  const GeoPlace({
    required this.pinCode,
    this.district,
    this.locality,
  });

  /// The full civic scope line, e.g. `Patna · Sadar · 800001`
  /// (DESIGN.md §7.2 masthead format).
  String get scopeLine => [
        if (locality != null && locality!.isNotEmpty) locality,
        if (district != null && district!.isNotEmpty) district,
        pinCode.value,
      ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is GeoPlace &&
      other.pinCode == pinCode &&
      other.district == district &&
      other.locality == locality;

  @override
  int get hashCode => Object.hash(pinCode, district, locality);

  @override
  String toString() => scopeLine;
}
