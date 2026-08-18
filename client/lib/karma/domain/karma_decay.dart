/// Monthly karma decay for INACTIVE accounts (PRD §9.2, Task 10.2).
///
/// Karma decays −2% per month for accounts with NO activity, preventing
/// permanent unchecked influence from dormant high-karma accounts.
///
/// Pure, deterministic, integer-only math: each inactive month multiplies
/// the score by 98/100 with truncating division, so the same score and
/// months always yield the same result on every device.
class KarmaDecay {
  const KarmaDecay._();

  /// The monthly decay percentage (2%).
  static const int percentPerMonth = 2;

  /// The running multiplier numerator/denominator (98/100).
  static const int _factorNumerator = 100 - percentPerMonth;
  static const int _factorDenominator = 100;

  /// Applies [monthsInactive] months of −2% decay to [score].
  ///
  /// score 100, 1 month → 98
  /// score 100, 2 months → 96
  /// score 100, 12 months → 78 (floor(96.08) → 96 * 98 ~/ 100 = 94.08 → 94...)
  ///   (integer truncation is deterministic and documented in tests)
  /// score 0 → 0
  static int decayed({required int score, required int monthsInactive}) {
    var result = score;
    for (var i = 0; i < monthsInactive; i++) {
      result = result * _factorNumerator ~/ _factorDenominator;
    }
    return result;
  }
}
