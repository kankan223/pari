import 'package:geocoding/geocoding.dart' as gc;
import 'package:geolocator/geolocator.dart' as gl;

import '../domain/geo_place.dart';
import '../domain/pin_code.dart';
import '../domain/pin_code_resolver.dart';

/// Production [PinCodeResolver] (Task 7.2) backed by `geolocator` +
/// `geocoding`.
///
/// SECURITY CHECKPOINT — this file is the ONLY place in the app that
/// touches raw device coordinates. It immediately collapses them into a
/// coarse [GeoPlace] (6-digit pin + district/locality names) and returns
/// ONLY that:
/// - raw positions (lat/lng/accuracy) are never returned,
/// - coordinates are never logged, stored, or uploaded,
/// - the pin code is the finest-grained signal the rest of the app sees.
///
/// No location data is ever used for fingerprinting: no device id, no
/// timing correlation, no coordinate history — one coarse scope, derived
/// on demand, held only in this call's local variables.
class GeolocatorPinCodeResolver implements PinCodeResolver {
  final GeoLocationService _location;
  final GeoCodingService _geocoder;

  GeolocatorPinCodeResolver({
    GeoLocationService? location,
    GeoCodingService? geocoder,
  })  : _location = location ?? const PluginGeoLocationService(),
        _geocoder = geocoder ?? const PluginGeoCodingService();

  @override
  Future<PinCodeResolution> resolveCurrentPlace() async {
    // 1. Permission — whileInUse is the minimum (we never need background
    //    location; the app is foreground-only).
    var permission = await _location.checkPermission();
    if (permission == gl.LocationPermission.denied) {
      permission = await _location.requestPermission();
    }
    if (permission == gl.LocationPermission.denied ||
        permission == gl.LocationPermission.deniedForever ||
        permission == gl.LocationPermission.unableToDetermine) {
      throw const PinCodeResolutionException('location_permission_denied');
    }

    // 2. Position — prefer a fresh fix with a short time limit; fall back
    //    to the last known position when a fresh fix is unavailable.
    gl.Position? position;
    try {
      position = await _location.getCurrentPosition(
        desiredAccuracy: gl.LocationAccuracy.low, // coarse is all we need
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      position = await _location.getLastKnownPosition();
    }
    if (position == null) {
      throw const PinCodeResolutionException('position_unavailable');
    }

    // 3. Reverse-geocode to a coarse placemark (NOT a street address).
    final placemarks = await _geocoder.placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    final pm = placemarks.isEmpty ? null : placemarks.first;

    final rawPin = pm?.postalCode;
    final pin = rawPin == null ? null : PinCode.tryParse(rawPin);
    if (pin == null) {
      throw const PinCodeResolutionException('postal_code_unavailable');
    }

    // 4. Collapse to the coarse civic scope. `subAdministrativeArea` is the
    //    district; `locality` is the town/city. Nothing finer is kept.
    return PinCodeResolution(
      place: GeoPlace(
        pinCode: pin,
        district: pm?.subAdministrativeArea ?? pm?.administrativeArea,
        locality: pm?.locality,
      ),
      source: PinCodeResolutionSource.location,
    );
  }
}

/// Seam over the `geolocator` static facade (test-injectable; the real
/// implementation delegates to the plugin).
abstract class GeoLocationService {
  const GeoLocationService();

  Future<gl.LocationPermission> checkPermission();

  Future<gl.LocationPermission> requestPermission();

  Future<gl.Position?> getCurrentPosition({
    gl.LocationAccuracy desiredAccuracy,
    Duration? timeLimit,
  });

  Future<gl.Position?> getLastKnownPosition();
}

/// Seam over the `geocoding` facade.
abstract class GeoCodingService {
  const GeoCodingService();

  Future<List<gc.Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  );
}

/// Real [GeoLocationService] — delegates to the `geolocator` static API.
class PluginGeoLocationService extends GeoLocationService {
  const PluginGeoLocationService();

  @override
  Future<gl.LocationPermission> checkPermission() =>
      gl.Geolocator.checkPermission();

  @override
  Future<gl.LocationPermission> requestPermission() =>
      gl.Geolocator.requestPermission();

  @override
  Future<gl.Position?> getCurrentPosition({
    gl.LocationAccuracy desiredAccuracy = gl.LocationAccuracy.best,
    Duration? timeLimit,
  }) =>
      gl.Geolocator.getCurrentPosition(
        desiredAccuracy: desiredAccuracy,
        timeLimit: timeLimit,
      );

  @override
  Future<gl.Position?> getLastKnownPosition() =>
      gl.Geolocator.getLastKnownPosition();
}

/// Real [GeoCodingService] — delegates to the `geocoding` facade.
class PluginGeoCodingService extends GeoCodingService {
  const PluginGeoCodingService();

  @override
  Future<List<gc.Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) =>
      gc.placemarkFromCoordinates(latitude, longitude);
}
