import '../domain/geo_place.dart';
import '../domain/pin_code_store.dart';

/// In-memory [PinCodeStore] (data layer, Task 7.2).
///
/// Local persistence seam for the resolved scope — the SQLCipher-backed
/// implementation lands with the Phase 7 data work. Stores ONLY the coarse
/// [GeoPlace] (pin + district/locality names) — never coordinates.
class LocalPinCodeStore implements PinCodeStore {
  GeoPlace? _place;

  LocalPinCodeStore({GeoPlace? initial}) : _place = initial;

  /// The current value (test/read access).
  GeoPlace? get current => _place;

  @override
  Future<GeoPlace?> read() async => _place;

  @override
  Future<void> write(GeoPlace place) async {
    _place = place;
  }
}
