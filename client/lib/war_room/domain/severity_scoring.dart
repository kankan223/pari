import 'case_intake.dart';
import 'case_severity.dart';

/// Keyword-based severity scoring engine (Task 8.4, MASTER_PLAN §8.4).
///
/// Replaces the Task 8.1 provisional hint with a DETERMINISTIC triage score:
/// the narrative is scanned for keyword signals per severity band, urgency
/// signals add weight, and the intake situation's base severity acts as a
/// FLOOR — a serious category can never be scored below its band. The engine
/// is pure: same input → same output, every time (SECURITY CHECKPOINT 8.4:
/// severity scoring is deterministic — verified by repeated-invocation tests).
///
/// SECURITY CHECKPOINT (8.1/8.3): the engine reads ONLY case content
/// (narrative + fixed category enums) and returns ONLY public severity
/// attributes + non-PII signal names. No identity, no payload bytes, no
/// raw PII ever enters or leaves the scorer.
class SeverityScorer {
  /// Signals that push a case toward CRITICAL — content that implies an
  /// ongoing, public, or irreversible harm.
  static const Set<String> criticalKeywords = {
    'leaked',
    'published',
    'posted',
    'went viral',
    'viral',
    'immediate danger',
    'in danger',
    'suicidal',
    'self-harm',
    'weapon',
    'kidnap',
    'kidnapped',
    'abducted',
    'life-threatening',
  };

  /// HIGH-band signals — extortion, threats, physical/intimate harm.
  static const Set<String> highKeywords = {
    'blackmail',
    'extortion',
    'threat',
    'threatened',
    'threatening',
    'intimate image',
    'explicit photo',
    'revenge porn',
    'nude',
    'harassment',
    'stalking',
    'stalk',
    'assault',
    'beaten',
    'money',
    'pay',
    'ransom',
    'deadline',
  };

  /// MEDIUM-band signals — fraud, impersonation, account takeover.
  static const Set<String> mediumKeywords = {
    'fake profile',
    'impersonation',
    'impersonating',
    'identity theft',
    'fraud',
    'scam',
    'hacked',
    'stolen',
    'account',
    'password',
    'blocked',
    'reported',
    'defamation',
    'rumor',
    'rumour',
  };

  /// Urgency signals — add weight toward the next band up.
  static const Set<String> urgencyKeywords = {
    'immediately',
    'tonight',
    'asap',
    'urgent',
    'today',
    'right now',
    'hours',
    'before',
    'by tomorrow',
  };

  const SeverityScorer();

  /// Scores [narrative] given the fixed intake category context. Pure and
  /// deterministic — identical inputs always yield identical output.
  ///
  /// [floorSeverity] is the situation-category base severity: the final
  /// score can never rank below it (a victim selecting "blackmail" cannot
  /// be auto-scored LOW because the narrative used neutral words).
  SeverityTriage score({
    required String narrative,
    required CaseSeverity floorSeverity,
    required IntakeUrgency urgency,
  }) {
    final lower = narrative.toLowerCase();

    final criticalHits = _countHits(lower, criticalKeywords);
    final highHits = _countHits(lower, highKeywords);
    final mediumHits = _countHits(lower, mediumKeywords);
    final urgencyHits = _countHits(lower, urgencyKeywords);

    // Band from keyword volume — deterministic rules:
    //  - 1+ CRITICAL keyword → critical.
    //  - 2+ HIGH keywords OR (1 HIGH + urgency) → high.
    //  - 1 HIGH or 2+ MEDIUM → medium.
    //  - otherwise → low.
    var scored = CaseSeverity.low;
    if (criticalHits >= 1) {
      scored = CaseSeverity.critical;
    } else if (highHits >= 2 || (highHits >= 1 && urgencyHits >= 1)) {
      scored = CaseSeverity.high;
    } else if (highHits >= 1 || mediumHits >= 2) {
      scored = CaseSeverity.medium;
    }

    // Urgency floor: an immediate threat can never be scored below its
    // urgency band (the intake already floors at critical).
    scored = CaseSeverity.maxSeverity(scored, urgency.floorSeverity);

    // Situation floor: never downgrade the selected category.
    scored = CaseSeverity.maxSeverity(scored, floorSeverity);

    return SeverityTriage(
      severity: scored,
      criticalSignals: criticalHits,
      highSignals: highHits,
      mediumSignals: mediumHits,
      urgencySignals: urgencyHits,
      slaHours: slaHoursFor(scored),
    );
  }

  /// The SLA target (hours to first report) for a severity — the single
  /// deterministic mapping used by the repository and the UI.
  static int slaHoursFor(CaseSeverity severity) => switch (severity) {
        CaseSeverity.critical => 24,
        CaseSeverity.high => 48,
        CaseSeverity.medium => 72,
        CaseSeverity.low => 120,
      };

  static int _countHits(String lower, Set<String> keywords) {
    var count = 0;
    for (final keyword in keywords) {
      // Whole-word / phrase containment counts. Fixed keyword lists only —
      // never user-derived patterns.
      if (lower.contains(keyword)) {
        count++;
      }
    }
    return count;
  }
}

/// The immutable result of a [SeverityScorer] triage pass (Task 8.4).
///
/// Carries ONLY public severity attributes + non-PII signal COUNTS and the
/// SLA projection. The matched keywords are never returned (they are case
/// content — the counts are the audit surface).
class SeverityTriage {
  final CaseSeverity severity;

  /// Number of distinct CRITICAL-band keyword signals matched.
  final int criticalSignals;

  /// Number of distinct HIGH-band keyword signals matched.
  final int highSignals;

  /// Number of distinct MEDIUM-band keyword signals matched.
  final int mediumSignals;

  /// Number of distinct urgency signals matched.
  final int urgencySignals;

  /// SLA target in hours for [severity].
  final int slaHours;

  const SeverityTriage({
    required this.severity,
    required this.criticalSignals,
    required this.highSignals,
    required this.mediumSignals,
    required this.urgencySignals,
    required this.slaHours,
  });

  /// Signal chips the UI may render (fixed labels, never keyword text).
  List<String> get signalLabels => [
        if (criticalSignals > 0) '$criticalSignals× CRITICAL signal',
        if (highSignals > 0) '$highSignals× HIGH signal',
        if (mediumSignals > 0) '$mediumSignals× MEDIUM signal',
        if (urgencySignals > 0) '$urgencySignals× urgency signal',
      ];
}

/// A human-reviewed severity override (Task 8.4 "severity override UI").
///
/// The analyst overrides the engine's auto-score with [newSeverity] and a
/// short [reason]; [at] is the override timestamp. Reason is analyst
/// annotation (case content, never identity) — no raw PII is enforced here
/// because the reason is free text; the PII pipeline (Task 8.3) scrubs
/// user-generated text before it is persisted.
class SeverityOverride {
  final CaseSeverity newSeverity;
  final String reason;
  final DateTime at;

  const SeverityOverride({
    required this.newSeverity,
    required this.reason,
    required this.at,
  });
}
