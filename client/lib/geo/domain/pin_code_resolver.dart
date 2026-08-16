import 'geo_place.dart';

/// Why a pin-code resolution produced its result.
enum PinCodeResolutionSource {
  /// Derived from the device location via reverse geocoding.
  location,

  /// The user entered / confirmed the pin manually.
  manual,

  /// A persisted pin from a previous session (offline fallback).
  persisted,
}

/// The outcome of a pin-code resolution attempt.
///
/// SECURITY CHECKPOINT (Task 7.2): this is the ONLY location-derived value
/// the rest of the app sees — a [GeoPlace] (coarse pin + civic names),
/// never coordinates.
class PinCodeResolution {
  final GeoPlace place;

  /// Null when the device refused/did not support location; the caller
  /// falls back to manual entry or the persisted pin.
  final PinCodeResolutionSource source;

  const PinCodeResolution({required this.place, required this.source});

  bool get fromLocation => source == PinCodeResolutionSource.location;
}

/// Geographic pin-code resolution boundary (port, Task 7.2).
///
/// The production implementation wraps `geolocator` + `geocoding` and
/// STRIPS the location down to a coarse [GeoPlace] before returning — the
/// resolver is the only file that ever touches raw coordinates. It throws
/// [PinCodeResolutionException] when the pin cannot be derived; callers
/// degrade to manual/persisted pin entry.
abstract class PinCodeResolver {
  /// Resolves the device's current coarse [GeoPlace] (pin code + district).
  ///
  /// Throws [PinCodeResolutionException] on permission denial, disabled
  /// location services, or a missing/unparseable postal code.
  Future<PinCodeResolution> resolveCurrentPlace();
}

/// Signals that the current location could not be resolved to a pin code.
class PinCodeResolutionException implements Exception {
  final String reason;

  const PinCodeResolutionException(this.reason);

  @override
  String toString() => 'PinCodeResolutionException($reason)';
}
