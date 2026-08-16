import 'package:civic_commons/geo/data/geolocator_pin_code_resolver.dart';
import 'package:civic_commons/geo/domain/pin_code_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart' as gc;
import 'package:geolocator/geolocator.dart' as gl;

/// Fake [GeoLocationService] — a granted-permission device at a fixed
/// coarse position.
class _FakeLocation extends GeoLocationService {
  _FakeLocation({this.permission, this.position, this.throwOnPosition = false});

  gl.LocationPermission? permission;
  gl.Position? position;
  bool throwOnPosition;

  int requestCalls = 0;

  @override
  Future<gl.LocationPermission> checkPermission() async =>
      permission ?? gl.LocationPermission.whileInUse;

  @override
  Future<gl.LocationPermission> requestPermission() async {
    requestCalls++;
    // A granted request upgrades the permission (simulates the OS prompt
    // being accepted).
    permission = gl.LocationPermission.whileInUse;
    return permission!;
  }

  @override
  Future<gl.Position?> getCurrentPosition({
    gl.LocationAccuracy desiredAccuracy = gl.LocationAccuracy.best,
    Duration? timeLimit,
  }) async {
    if (throwOnPosition) {
      throw Exception('timeout');
    }
    return position;
  }

  @override
  Future<gl.Position?> getLastKnownPosition() async => position;
}

/// Fake [GeoCodingService] — returns a fixed coarse placemark.
class _FakeGeocoder extends GeoCodingService {
  _FakeGeocoder({this.postalCode = '800001', this.empty = false});

  final String? postalCode;
  final bool empty;
  double? lastLat;
  double? lastLng;

  @override
  Future<List<gc.Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    lastLat = latitude;
    lastLng = longitude;
    if (empty) {
      return const [];
    }
    return [
      gc.Placemark(
        postalCode: postalCode,
        administrativeArea: 'Bihar',
        subAdministrativeArea: 'Patna',
        locality: 'Patna',
        name: 'Boring Road', // street-level detail is DISCARDED
        street: 'Boring Road',
        subLocality: 'Sadar',
      ),
    ];
  }
}

gl.Position _position() => gl.Position(
      latitude: 25.61,
      longitude: 85.14,
      timestamp: DateTime.utc(2026, 8, 10),
      accuracy: 4.0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  group('GeolocatorPinCodeResolver (Task 7.2)', () {
    test('resolves coordinates to a coarse pin + district (never finer)',
        () async {
      final geocoder = _FakeGeocoder();
      final resolver = GeolocatorPinCodeResolver(
        location: _FakeLocation(position: _position()),
        geocoder: geocoder,
      );

      final resolution = await resolver.resolveCurrentPlace();

      expect(resolution.source, PinCodeResolutionSource.location);
      expect(resolution.place.pinCode.value, '800001');
      expect(resolution.place.district, 'Patna'); // subAdministrativeArea
      expect(resolution.place.locality, 'Patna');
      // The street-level name/sub-locality are stripped — only coarse
      // civic names survive the boundary.
      expect(resolution.place.scopeLine.contains('Boring Road'), isFalse);
      expect(geocoder.lastLat, 25.61);
    });

    test('requests permission when initially denied, then resolves', () async {
      final location = _FakeLocation(
        permission: gl.LocationPermission.denied,
        position: _position(),
      );
      final resolver = GeolocatorPinCodeResolver(
        location: location,
        geocoder: _FakeGeocoder(),
      );

      final resolution = await resolver.resolveCurrentPlace();

      expect(location.requestCalls, 1);
      expect(resolution.place.pinCode.value, '800001');
    });

    test('permission denied → PinCodeResolutionException', () async {
      final resolver = GeolocatorPinCodeResolver(
        location: _FakeLocation(
          permission: gl.LocationPermission.deniedForever,
          position: _position(),
        ),
        geocoder: _FakeGeocoder(),
      );

      expect(
        resolver.resolveCurrentPlace(),
        throwsA(isA<PinCodeResolutionException>()),
      );
    });

    test('position timeout falls back to the last known position', () async {
      final location = _FakeLocation(
        position: _position(),
        throwOnPosition: true,
      );
      final resolver = GeolocatorPinCodeResolver(
        location: location,
        geocoder: _FakeGeocoder(),
      );

      final resolution = await resolver.resolveCurrentPlace();

      expect(resolution.place.pinCode.value, '800001');
    });

    test('missing position → PinCodeResolutionException', () async {
      final resolver = GeolocatorPinCodeResolver(
        location: _FakeLocation(position: null),
        geocoder: _FakeGeocoder(),
      );

      expect(
        resolver.resolveCurrentPlace(),
        throwsA(isA<PinCodeResolutionException>()),
      );
    });

    test('malformed / missing postal code → PinCodeResolutionException',
        () async {
      final resolver = GeolocatorPinCodeResolver(
        location: _FakeLocation(position: _position()),
        geocoder: _FakeGeocoder(postalCode: 'not-a-pin'),
      );

      expect(
        resolver.resolveCurrentPlace(),
        throwsA(isA<PinCodeResolutionException>()),
      );
    });

    test('empty placemark list → PinCodeResolutionException', () async {
      final resolver = GeolocatorPinCodeResolver(
        location: _FakeLocation(position: _position()),
        geocoder: _FakeGeocoder(empty: true),
      );

      expect(
        resolver.resolveCurrentPlace(),
        throwsA(isA<PinCodeResolutionException>()),
      );
    });

    test('real plugin seams delegate to the geolocator/geocoding facades',
        () async {
      // The plugin wrappers are thin static delegates — verify they are
      // wired to the plugin types (no-op at runtime without a device, but
      // the plumbing is type-correct).
      expect(const PluginGeoLocationService(), isA<GeoLocationService>());
      expect(const PluginGeoCodingService(), isA<GeoCodingService>());
    });
  });
}
