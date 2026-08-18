import '../../karma/domain/karma_action.dart';
import '../../karma/domain/karma_gate.dart';

/// Karma engine phases (Task 10.2).
enum KarmaPhase {
  /// Not started.
  idle,

  /// Reading the local ledger.
  loading,

  /// The balance + gates + recent activity are projected.
  ready,

  /// A local source failed — generic, payload-free error.
  error,
}

/// Karma tier bands (DESIGN.md §4.3 KarmaBadge).
enum KarmaTier {
  /// 0–49 — outline ring, muted.
  citizen('Citizen', 0),

  /// 50–99 — half-fill ring, Civic Gold.
  contributor('Contributor', 50),

  /// 100–149 — full ring, Civic Gold.
  validator('Validator', 100),

  /// 150–499 — star ring, Civic Gold + Vault Blue border.
  analyst('Analyst', 150),

  /// 500+ — hexagon ring, Ink fill, Civic Gold glyph.
  council('Council', 500);

  const KarmaTier(this.label, this.minimum);

  /// Fixed, non-sensitive display label.
  final String label;

  /// The minimum balance for this tier.
  final int minimum;

  /// The tier for [balance] (deterministic, monotone in balance).
  static KarmaTier forBalance(int balance) {
    if (balance >= KarmaTier.council.minimum) {
      return KarmaTier.council;
    }
    if (balance >= KarmaTier.analyst.minimum) {
      return KarmaTier.analyst;
    }
    if (balance >= KarmaTier.validator.minimum) {
      return KarmaTier.validator;
    }
    if (balance >= KarmaTier.contributor.minimum) {
      return KarmaTier.contributor;
    }
    return KarmaTier.citizen;
  }
}

/// A UI-safe karma activity row (Task 10.2).
///
/// SECURITY CHECKPOINT (10.2): the projection carries ONLY the fixed action
/// label + the integer delta + the timestamp — NO actor hash, NO blind
/// handle, NO identity fragment. The full event's actor is never rendered.
class KarmaActivity {
  final KarmaAction action;
  final int delta;
  final DateTime at;

  const KarmaActivity({
    required this.action,
    required this.delta,
    required this.at,
  });
}

/// Immutable BLoC state for the karma status screen (Task 10.2).
///
/// SECURITY CHECKPOINT (10.2): the state carries ONLY the public integer
/// balance, the deterministic tier, the gate satisfaction map, and the
/// UI-safe activity projections (fixed labels + deltas + timestamps). No
/// blind hash, no event ids, no identity fragments, no payload bytes.
class KarmaState {
  final KarmaPhase phase;

  /// The public karma balance.
  final int balance;

  /// Per-gate satisfaction (score + tenure check).
  final Map<KarmaGate, bool> gates;

  /// Most-recent-first UI-safe activity rows (bounded).
  final List<KarmaActivity> activity;

  /// GENERIC error message — never a payload, never internal detail.
  final String? errorMessage;

  const KarmaState({
    this.phase = KarmaPhase.idle,
    this.balance = 0,
    this.gates = const {},
    this.activity = const [],
    this.errorMessage,
  });

  /// The deterministic tier band for [balance] (DESIGN.md §4.3).
  KarmaTier get tier => KarmaTier.forBalance(balance);

  const KarmaState.idle() : this();

  const KarmaState.loading() : this(phase: KarmaPhase.loading);

  const KarmaState.ready({
    required this.balance,
    required this.gates,
    required this.activity,
  })  : phase = KarmaPhase.ready,
        errorMessage = null;

  const KarmaState.error(String this.errorMessage)
      : phase = KarmaPhase.error,
        balance = 0,
        gates = const {},
        activity = const [];

  bool get isIdle => phase == KarmaPhase.idle;
  bool get isLoading => phase == KarmaPhase.loading;
  bool get isReady => phase == KarmaPhase.ready;
  bool get isError => phase == KarmaPhase.error;

  /// Whether [gate] is satisfied in this state (false outside ready).
  bool satisfied(KarmaGate gate) => gates[gate] ?? false;
}
