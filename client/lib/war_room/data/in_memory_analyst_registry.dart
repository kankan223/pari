import '../domain/analyst.dart';
import '../domain/analyst_registry.dart';

/// In-memory, LOCAL-FIRST [AnalystRegistry] (data layer, Task 8.5).
///
/// Seeds a pool of blinded analysts (fixed handles, skill tags, vetting
/// status, case caps) and implements the deterministic assignment engine:
///
/// - Skill matching: an analyst must carry the required skill.
/// - Load tracking: an analyst at [Analyst.caseCap] is never assigned.
/// - Determinism: among eligible analysts, the least-loaded wins; ties
///   break by blinded handle ascending — identical pools always yield the
///   same assignment (SECURITY CHECKPOINT 8.5: assignment is deterministic).
///
/// SECURITY CHECKPOINT (8.5): analysts carry ONLY generated blinded handles
/// (`AN-0042`), skill tags, and counts. No name/email/phone/hash ever
/// exists in this store — a victim can never see who is on their case.
class InMemoryAnalystRegistry implements AnalystRegistry {
  final Map<String, Analyst> _analysts = {};
  final Map<String, Set<String>> _caseAssignments = {};

  /// The deterministic CTF vetting gauntlet (injectable for tests).
  final AnalystVettingGauntlet _gauntlet;

  InMemoryAnalystRegistry({
    List<Analyst> seed = const [],
    AnalystVettingGauntlet gauntlet = const AnalystVettingGauntlet(),
  }) : _gauntlet = gauntlet {
    for (final a in seed) {
      _analysts[a.analystId] = a;
    }
  }

  /// The canonical production pool: six blinded, vetted analysts spanning
  /// the skill tags with distinct caps. Fixed — deterministic assignment
  /// depends on a stable pool.
  static InMemoryAnalystRegistry production() => InMemoryAnalystRegistry(
        seed: [
          for (var i = 1; i <= 6; i++)
            Analyst(
              analystId: 'AN-${i.toString().padLeft(4, '0')}',
              skills: _skillsFor(i),
              vettingStatus: AnalystVettingStatus.vetted,
              gauntletScore: 92,
              caseCap: 3,
            ),
        ],
      );

  static Set<AnalystSkill> _skillsFor(int i) => switch (i) {
        1 => {AnalystSkill.osint, AnalystSkill.threatAssessment},
        2 => {AnalystSkill.platformTakedown, AnalystSkill.crisisSupport},
        3 => {AnalystSkill.threatAssessment, AnalystSkill.crisisSupport},
        4 => {AnalystSkill.platformTakedown, AnalystSkill.digitalForensics},
        5 => {AnalystSkill.digitalForensics, AnalystSkill.osint},
        _ => {AnalystSkill.osint},
      };

  @override
  Future<List<Analyst>> listAnalysts() async =>
      _analysts.values.toList(growable: false);

  @override
  Future<Analyst?> analystById(String analystId) async => _analysts[analystId];

  @override
  Future<List<CaseAssignment>> assignToCase({
    required String caseNumber,
    required List<AnalystSkill> skills,
    required DateTime at,
  }) async {
    final assignments = <CaseAssignment>[];
    for (final skill in skills) {
      // Eligibility: vetted, carries the skill, and either already on this
      // case (an additional skill slot on the SAME case is one workload —
      // the cap counts concurrent CASES, not slots) or under the cap.
      final eligible = _analysts.values
          .where((a) =>
              a.vettingStatus == AnalystVettingStatus.vetted &&
              a.skills.contains(skill) &&
              (a.activeCaseCount < a.caseCap ||
                  (_caseAssignments[caseNumber]?.contains(a.analystId) ??
                      false)))
          .toList()
        // Deterministic pick: least-loaded first, ties by handle ascending.
        ..sort((a, b) {
          final byLoad = a.activeCaseCount.compareTo(b.activeCaseCount);
          if (byLoad != 0) {
            return byLoad;
          }
          return a.analystId.compareTo(b.analystId);
        });

      if (eligible.isEmpty) {
        // No vetted analyst has capacity for this skill — the case gets
        // whatever coverage exists; the gap is surfaced in the UI.
        continue;
      }
      final chosen = eligible.first;
      // Load tracks CASES, not skill-slots: an analyst already on this case
      // (picked for an earlier skill) is not double-counted.
      final alreadyOnCase =
          _caseAssignments[caseNumber]?.contains(chosen.analystId) ?? false;
      if (!alreadyOnCase) {
        _analysts[chosen.analystId] = chosen.withIncrementedLoad();
      }
      _caseAssignments
          .putIfAbsent(caseNumber, () => <String>{})
          .add(chosen.analystId);
      assignments.add(CaseAssignment(
        caseNumber: caseNumber,
        analystId: chosen.analystId,
        skill: skill,
        assignedAt: at,
      ));
    }
    return assignments;
  }

  @override
  Future<void> releaseFromCase({
    required String caseNumber,
    required String analystId,
  }) async {
    final analyst = _analysts[analystId];
    if (analyst == null) {
      return;
    }
    _analysts[analystId] = analyst.withDecrementedLoad();
    _caseAssignments[caseNumber]?.remove(analystId);
  }

  @override
  Future<Analyst> runGauntlet({
    required String analystId,
    required GauntletAttempt attempt,
  }) async {
    final analyst = _analysts[analystId];
    if (analyst == null) {
      throw StateError('unknown analyst: $analystId');
    }
    final score = _gauntlet.score(attempt);
    if (!_gauntlet.passes(attempt)) {
      // Failing the sandbox never changes state — the analyst stays pending
      // and can retry (deterministic: same attempt → same result).
      return analyst;
    }
    final updated = analyst.withVetting(score);
    _analysts[analystId] = updated;
    return updated;
  }
}
