import 'package:flutter/foundation.dart' show visibleForTesting;

/// A validated Indian 6-digit postal index (DESIGN.md §7.2, FR-L2).
///
/// The pin code is the Ledger's COARSE civic scope — the only location
/// signal that ever leaves the device. It is public civic information
/// (printed on every envelope), NOT PII.
///
/// SECURITY CHECKPOINT (Task 7.2): exact device coordinates are never
/// derived into anything finer than a pin code; a `PinCode` can never
/// encode latitude/longitude or a street address.
class PinCode {
  final String value;

  const PinCode._(this.value);

  /// Strict 6-digit Indian pin (100000–999999).
  static final RegExp _pattern = RegExp(r'^[1-9]\d{5}$');

  /// Validates [raw] and returns a [PinCode], or null when malformed
  /// (non-6-digit / leading zero).
  static PinCode? tryParse(String raw) {
    final trimmed = raw.trim();
    if (!_pattern.hasMatch(trimmed)) {
      return null;
    }
    return PinCode._(trimmed);
  }

  /// Parses [raw], throwing [ArgumentError] on malformed input.
  static PinCode parse(String raw) {
    final pin = tryParse(raw);
    if (pin == null) {
      throw ArgumentError.value(raw, 'raw', 'Not a valid 6-digit pin code');
    }
    return pin;
  }

  /// Test-only factory — validates via [tryParse] at runtime (avoids the
  /// private-constructor-in-const-literal restriction across libraries).
  @visibleForTesting
  static PinCode forTest(String value) {
    final pin = tryParse(value);
    if (pin == null) {
      throw ArgumentError.value(value, 'value', 'Bad test pin fixture');
    }
    return pin;
  }

  /// The first two digits encode the postal circle (state/region) — a
  /// coarse ~state grain used for district fallback queries, never
  /// anything finer.
  String get circlePrefix => value.substring(0, 2);

  @override
  bool operator ==(Object other) => other is PinCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
