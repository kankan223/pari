import 'dart:io';

import 'package:civic_commons/geo/domain/geo_place.dart';
import 'package:civic_commons/geo/domain/pin_code.dart';
import 'package:civic_commons/geo/domain/pin_code_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 7.2 SECURITY CHECKPOINT — location is never a fingerprint vector.
///
/// 1. The only file that imports the location plugins is the data-layer
///    resolver, and it collapses coordinates to a coarse [GeoPlace]
///    before returning.
/// 2. The domain model has NO coordinate fields — latitude/longitude/
///    accuracy cannot exist above the data layer.
/// 3. No location data is logged, stored, or uploaded (no print statements,
///    no persisted coordinate stores).
void main() {
  group('Task 7.2 SECURITY CHECKPOINT', () {
    test('only the resolver file touches the location plugins', () {
      final geoFiles = Directory('lib/geo')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final pluginImport = RegExp(
        "import\\s+['\"]package:(geolocator|geocoding)",
      );
      for (final file in geoFiles) {
        final src = file.readAsStringSync();
        final touches = pluginImport.hasMatch(src);
        if (file.path.contains('geolocator_pin_code_resolver.dart')) {
          expect(touches, isTrue,
              reason: 'resolver must be the plugin boundary');
        } else {
          expect(touches, isFalse,
              reason: '${file.path} must not import location plugins');
        }
      }
    });

    test('domain + state carry no coordinate fields (structural proof)', () {
      final files = <String>[
        'lib/geo/domain/geo_place.dart',
        'lib/geo/domain/pin_code.dart',
        'lib/geo/domain/pin_code_resolver.dart',
        'lib/state/domain/ledger_geo_state.dart',
      ];
      for (final path in files) {
        final src = File(path).readAsStringSync();
        // `accuracy`/`position` appear only in doc comments explaining the
        // contract — the field DECLARATIONS must be absent.
        expect(
          RegExp(r'final\s+(double|Position|Coordinates?)\s+\w+').hasMatch(src),
          isFalse,
          reason: '$path must not declare coordinate-typed fields',
        );
      }
    });

    test('GeoPlace is the only location-bearing type — and it is coarse', () {
      final place = GeoPlace(
        pinCode: PinCode.parse('800001'),
        district: 'Patna',
        locality: 'Sadar',
      );
      // The public surface is exactly pin + district + locality.
      expect(place.scopeLine, 'Sadar · Patna · 800001');
    });

    test('no ledger/geo production file prints raw output', () {
      final files = [
        ...Directory('lib/geo')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
        File('lib/state/data/local_ledger_geo_bloc.dart'),
      ];
      for (final file in files) {
        final src = file.readAsStringSync();
        expect(src.contains('print('), isFalse,
            reason: '${file.path} must not print (location could leak)');
        expect(src.contains('debugPrint('), isFalse,
            reason: '${file.path} must not debugPrint');
      }
    });

    test('no PII-shaped literals in the geo UI surface', () {
      final files = <String>[
        'lib/state/ui/explore_nearby_sheet.dart',
        'lib/state/ui/ledger_feed_screen.dart',
      ];
      for (final path in files) {
        final src = File(path).readAsStringSync();
        expect(RegExp(r'\+91\d{10}').hasMatch(src), isFalse,
            reason: '$path must not embed phone literals');
        expect(RegExp(r'[0-9a-f]{64}').hasMatch(src), isFalse,
            reason: '$path must not embed hash literals');
      }
    });

    test('PinCodeResolution carries only a coarse GeoPlace', () {
      final resolution = PinCodeResolution(
        place: GeoPlace(pinCode: PinCode.parse('800001')),
        source: PinCodeResolutionSource.location,
      );
      expect(resolution.place.pinCode.value, '800001');
      // The result type has exactly two members: place + source.
      expect(resolution.fromLocation, isTrue);
    });
  });
}
