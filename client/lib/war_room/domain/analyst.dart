import 'case_intake.dart';

/// Skill tags an analyst can carry (Task 8.5 "skill-tag matched assignment").
///
/// Skills are FIXED, non-sensitive labels — never identity. The mapping from
/// an [IntakeSituation] to the skills it needs is deterministic (a pure
/// constant table) so assignment is stable across devices and runs.
enum AnalystSkill {
  osint('OSINT'),
  platformTakedown('Platform takedown'),
  threatAssessment('Threat assessment'),
  legalAdvocacy('Legal advocacy'),
  crisisSupport('Crisis support'),
  digitalForensics('Digital forensics');

  const AnalystSkill(this.label);

  /// The UI label (fixed, non-sensitive).
  final String label;

  /// The skill tags REQUIRED to handle an intake situation — a deterministic
  /// constant map (never user-derived). Used by the assignment engine to
  /// pick analysts whose skills match the case.
  static List<AnalystSkill> forSituation(IntakeSituation situation) =>
      switch (situation) {
        IntakeSituation.blackmailExtortion => [
            AnalystSkill.threatAssessment,
            AnalystSkill.osint,
          ],
        IntakeSituation.intimateImageThreat => [
            AnalystSkill.platformTakedown,
            AnalystSkill.crisisSupport,
          ],
        IntakeSituation.fakeProfile => [
            AnalystSkill.platformTakedown,
            AnalystSkill.digitalForensics,
          ],
        IntakeSituation.threateningMessages => [
            AnalystSkill.threatAssessment,
            AnalystSkill.crisisSupport,
          ],
        IntakeSituation.tracingHarasser => [
            AnalystSkill.digitalForensics,
            AnalystSkill.osint,
          ],
        IntakeSituation.somethingElse => [AnalystSkill.osint],
      };
}

/// Analyst vetting lifecycle (Task 8.5 "analyst vetting gauntlet").
///
/// A candidate starts [pending]; only a passing gauntlet run promotes them
/// to [vetted]. Assignment NEVER picks a non-vetted analyst. Rejected is
/// reserved for a failed sandbox (not used by the deterministic engine yet —
/// pending/vetted cover the CTF gate).
enum AnalystVettingStatus {
  pending('PENDING VETTING'),
  vetted('VETTED'),
  rejected('REJECTED');

  const AnalystVettingStatus(this.label);

  /// Fixed classification strip label (never identity).
  final String label;
}

/// A CTF-style sandbox scenario (Task 8.5 "analyst vetting gauntlet").
///
/// The scenario embeds a fixed set of [threatMarkers] a competent analyst
/// must identify. The candidate's attempt names markers; the gauntlet
/// scores the intersection against the expected set. Everything is
/// deterministic — no randomness, no wall-clock — so a score is
/// reproducible across runs (SECURITY CHECKPOINT 8.5: vetting is
/// deterministic).
class GauntletScenario {
  /// Fixed scenario id (e.g. `GAUNTLET-01`) — never identity.
  final String scenarioId;

  /// The threat markers a passing analyst MUST identify (fixed, public
  /// scenario content — sandbox data, not PII).
  final Set<String> threatMarkers;

  const GauntletScenario({
    required this.scenarioId,
    required this.threatMarkers,
  });
}

/// The candidate's sandbox attempt — the markers they named (Task 8.5).
class GauntletAttempt {
  final String scenarioId;

  /// Markers the candidate identified (sandbox answers — scenario content).
  final Set<String> identifiedMarkers;

  const GauntletAttempt({
    required this.scenarioId,
    required this.identifiedMarkers,
  });
}

/// Deterministic CTF-style vetting gauntlet (Task 8.5).
///
/// Scores an [GauntletAttempt] against the scenario's expected threat
/// markers: `score = correct / expected * 100`. A score >= [passThreshold]
/// (80) passes the sandbox and promotes the analyst to vetted. Pure —
/// identical attempts always yield identical scores.
class AnalystVettingGauntlet {
  /// The passing score.
  static const int passThreshold = 80;

  /// The built-in sandbox scenarios (fixed, deterministic).
  static const List<GauntletScenario> scenarios = [
    GauntletScenario(
      scenarioId: 'GAUNTLET-01',
      threatMarkers: {
        'suspicious_short_url',
        'sender_spoofing',
        'credential_phish',
        'geo_tagged_photo',
      },
    ),
  ];

  const AnalystVettingGauntlet();

  /// The scenario by id, or null when unknown.
  GauntletScenario? scenarioFor(String scenarioId) {
    for (final s in scenarios) {
      if (s.scenarioId == scenarioId) {
        return s;
      }
    }
    return null;
  }

  /// Scores the attempt 0..100. Unknown scenario → 0 (cannot pass).
  int score(GauntletAttempt attempt) {
    final scenario = scenarioFor(attempt.scenarioId);
    if (scenario == null || scenario.threatMarkers.isEmpty) {
      return 0;
    }
    final correct = attempt.identifiedMarkers
        .where(scenario.threatMarkers.contains)
        .toSet()
        .length;
    return (correct * 100 / scenario.threatMarkers.length).floor();
  }

  /// True when the attempt meets the passing threshold.
  bool passes(GauntletAttempt attempt) => score(attempt) >= passThreshold;
}

/// A blinded analyst (Task 8.5).
///
/// SECURITY CHECKPOINT (8.5): the analyst carries ONLY a generated blinded
/// handle ([analystId] like `AN-0042`), skill tags, vetting status, and
/// load counters. NO name, email, phone, blind hash, or device identifier
/// ever lives on this model — victims see only the handle.
class Analyst {
  /// Generated blinded handle, e.g. `AN-0042` (sequence-derived, never
  /// identity-derived).
  final String analystId;

  /// Skill tags this analyst is vetted for.
  final Set<AnalystSkill> skills;

  final AnalystVettingStatus vettingStatus;

  /// The gauntlet score that earned vetting (0 when pending).
  final int gauntletScore;

  /// Current concurrent case load (count, never case content).
  final int activeCaseCount;

  /// Maximum concurrent cases this analyst may carry.
  final int caseCap;

  const Analyst({
    required this.analystId,
    required this.skills,
    this.vettingStatus = AnalystVettingStatus.pending,
    this.gauntletScore = 0,
    this.activeCaseCount = 0,
    this.caseCap = 3,
  });

  /// True when the analyst is vetted and has capacity for one more case.
  bool get availableForAssignment =>
      vettingStatus == AnalystVettingStatus.vetted && activeCaseCount < caseCap;

  /// A copy with an incremented load (after a case assignment).
  Analyst withIncrementedLoad() => Analyst(
        analystId: analystId,
        skills: skills,
        vettingStatus: vettingStatus,
        gauntletScore: gauntletScore,
        activeCaseCount: activeCaseCount + 1,
        caseCap: caseCap,
      );

  /// A copy with a decremented load (never below zero).
  Analyst withDecrementedLoad() => Analyst(
        analystId: analystId,
        skills: skills,
        vettingStatus: vettingStatus,
        gauntletScore: gauntletScore,
        activeCaseCount: (activeCaseCount - 1).clamp(0, caseCap),
        caseCap: caseCap,
      );

  /// A copy promoted to vetted with the gauntlet score that earned it.
  Analyst withVetting(int score) => Analyst(
        analystId: analystId,
        skills: skills,
        vettingStatus: AnalystVettingStatus.vetted,
        gauntletScore: score,
        activeCaseCount: activeCaseCount,
        caseCap: caseCap,
      );
}

/// A skill-matched case assignment (Task 8.5).
///
/// Carries the case stamp, the BLINDED analyst handle, the matched skill,
/// and the assignment timestamp — zero identity.
class CaseAssignment {
  final String caseNumber;
  final String analystId;
  final AnalystSkill skill;
  final DateTime assignedAt;

  const CaseAssignment({
    required this.caseNumber,
    required this.analystId,
    required this.skill,
    required this.assignedAt,
  });
}

/// A blinded analyst update note (extended in Task 8.5).
///
/// The note is attributed ONLY via the blinded [analystId] handle — never a
/// real identity. This is the blind-review contract: an analyst's note is
/// visible to the victim as a blinded card, and no note ever names another
/// analyst (enforced by the repository: the update is written with the
/// authoring analyst's handle only, and the registry never exposes names).
class AnalystUpdate {
  /// The BLINDED author handle (e.g. `AN-0042`) — the only attribution.
  final String analystId;

  final String text;
  final DateTime at;

  /// Progress chip label (e.g. `In progress`, `Done`) — public status only.
  final String progress;

  const AnalystUpdate({
    required this.analystId,
    required this.text,
    required this.at,
    required this.progress,
  });
}
