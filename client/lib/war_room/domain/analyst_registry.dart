import 'analyst.dart';

/// Registry port for the analyst pool (Task 8.5).
///
/// Clean architecture: the UI/state never talks to this directly — the case
/// repository consumes it at `fileCase` (and re-assignment) so cases carry
/// their assignments. The registry is the ONLY place analyst load and
/// vetting state live.
///
/// SECURITY CHECKPOINT (8.5): every method returns ONLY blinded [Analyst]
/// records (generated `AN-####` handles + skills + counts) — never names,
/// emails, phones, or hashes. The victim-facing surface is the assignment
/// on the case, which carries the handle only.
abstract class AnalystRegistry {
  /// All analysts (blinded records).
  Future<List<Analyst>> listAnalysts();

  /// Assigns up to one vetted analyst per required skill to [caseNumber]:
  /// for each skill in [skills] (in order), the least-loaded vetted analyst
  /// carrying that skill under their case cap wins. Tie-breaks by blinded
  /// handle ascending so assignment is deterministic. Returns the created
  /// assignments (empty when no vetted analyst has capacity).
  Future<List<CaseAssignment>> assignToCase({
    required String caseNumber,
    required List<AnalystSkill> skills,
    required DateTime at,
  });

  /// Releases the case from the analyst's load (withdrawn/closed cases).
  Future<void> releaseFromCase({
    required String caseNumber,
    required String analystId,
  });

  /// Runs the vetting gauntlet for [analystId] with [attempt]; a passing
  /// score promotes the analyst to vetted. Returns the updated record.
  Future<Analyst> runGauntlet({
    required String analystId,
    required GauntletAttempt attempt,
  });

  /// A single blinded analyst by handle, or null.
  Future<Analyst?> analystById(String analystId);
}
