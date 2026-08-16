import '../domain/pii_redaction.dart';
import '../domain/pii_pipeline_port.dart';

/// In-memory LOCAL contextual PII detector (Task 8.3, skill step 2).
///
/// This is the deterministic stand-in for the on-device Gemma slot: it
/// detects person names (bounded dictionary) and coarse address patterns
/// (street/road/lane/near/opposite/city suffixes) — the contextual PII the
/// regex dictionary cannot name. It runs entirely on-device: no cloud AI,
/// no network, no model download.
///
/// SECURITY CHECKPOINT: [detect] is called ONLY with ALREADY-REDACTED text
/// (the deterministic pass runs first), so a raw phone, e-mail, or gov ID
/// can never reach this detector — the AI Boundary Rule holds even for the
/// model slot. Detection is case-insensitive and returns category+offset
/// spans only (never matched plaintext).
class DictionaryPiiDetector implements ContextualPiiDetector {
  /// Bounded, curated name dictionary (common Indian names). Deliberately
  /// small: it exists to make the pipeline deterministic and testable — the
  /// real on-device model (same port) widens recall at deployment.
  static const Set<String> defaultNames = {
    'rahul',
    'priya',
    'amit',
    'sunita',
    'rajesh',
    'anita',
    'vijay',
    'kavita',
    'arjun',
    'deepa',
    'suresh',
    'meena',
    'ashok',
    'geeta',
    'vikram',
    'puja',
    'sanjay',
    'rekha',
    'mahesh',
    'neha',
  };

  /// Coarse address cue words (English + Hinglish street markers).
  static const Set<String> addressCues = {
    'street',
    'road',
    'lane',
    'gali',
    'marg',
    'nagar',
    'colony',
    'apartment',
    'flat',
    'opposite',
    'near',
    'behind',
    'sector',
  };

  final Set<String> _names;
  final Set<String> _addressCues;

  const DictionaryPiiDetector({
    Set<String> names = defaultNames,
    Set<String> addressCues = addressCues,
  })  : _names = names,
        _addressCues = addressCues;

  @override
  List<RedactedSpan> detect(String alreadyRedactedText) {
    final spans = <RedactedSpan>[];
    final lower = alreadyRedactedText.toLowerCase();

    // Names: whole-word matches against the bounded dictionary.
    for (final name in _names) {
      final pattern = RegExp('(?<![a-z])$name(?![a-z])');
      for (final match in pattern.allMatches(lower)) {
        // Map the match back onto the original (same length — only case
        // differs) text offsets.
        spans.add(RedactedSpan(
          category: PiiCategory.personName,
          start: match.start,
          end: match.end,
        ));
      }
    }

    // Addresses: "<word> <cue>" (e.g. "MG Road", "Sector 14", "near Lake").
    // Case-insensitive so "MG Road" and "mg road" both match; the lookarounds
    // keep "near" inside a longer word from matching.
    for (final cue in _addressCues) {
      final pattern = RegExp(
        '(?<![a-z])[a-z0-9]{2,} $cue(?![a-z])',
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(lower)) {
        spans.add(RedactedSpan(
          category: PiiCategory.address,
          start: match.start,
          end: match.end,
        ));
      }
    }

    spans
        .sort((a, b) => a.start != b.start ? a.start - b.start : b.end - a.end);
    final merged = <RedactedSpan>[];
    for (final span in spans) {
      if (merged.isNotEmpty && span.start < merged.last.end) {
        continue;
      }
      merged.add(span);
    }
    return merged;
  }
}
