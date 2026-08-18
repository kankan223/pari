import 'dart:async';

import '../../karma/domain/karma_action.dart';
import '../../karma/domain/karma_event.dart';
import '../../karma/domain/karma_gate.dart';
import '../../karma/domain/karma_repository.dart';
import '../domain/karma_bloc.dart';
import '../domain/karma_state.dart';

/// [KarmaRepository]-backed [KarmaBloc] (data layer, Task 10.2).
///
/// Reads the append-only ledger through the injected repository; projects
/// the balance, the deterministic tier, the per-gate satisfaction (using the
/// local account-age source), and the most-recent activity rows. Failures
/// degrade to the GENERIC error state — never a payload, never internal
/// detail. A monotonic sequence drops stale refreshes so an older, slower
/// read can never overwrite a newer one.
class LocalKarmaBloc implements KarmaBloc {
  final KarmaRepository _repository;

  /// Local account tenure in days (public, non-PII — gates need it for the
  /// Moderator Council). Injected so tests control it deterministically.
  final int accountAgeDays;

  /// Max activity rows kept in the UI-safe projection.
  static const int maxActivityRows = 20;

  final StreamController<KarmaState> _controller =
      StreamController<KarmaState>.broadcast();
  KarmaState _current = const KarmaState.idle();
  int _seq = 0;
  bool _closed = false;

  LocalKarmaBloc({
    required KarmaRepository repository,
    this.accountAgeDays = 0,
    Future<String> Function()? localActorHash,
  })  : _repository = repository,
        localActorHash = localActorHash ?? _throwMissingActor;

  @override
  Stream<KarmaState> get state => _controller.stream;

  @override
  KarmaState get current => _current;

  @override
  Future<void> refresh() async {
    if (_closed) {
      return;
    }
    final seq = ++_seq;
    _emit(const KarmaState.loading());
    try {
      final events = await _repository.events();
      if (_closed || seq != _seq) {
        return; // stale — a newer refresh superseded this one.
      }
      final balance = events.isEmpty ? 0 : events.last.balanceAfter;
      final gates = {
        for (final gate in KarmaGate.values)
          gate:
              gate.isSatisfied(karma: balance, accountAgeDays: accountAgeDays),
      };
      final activity = _projectActivity(events);
      _emit(KarmaState.ready(
        balance: balance,
        gates: gates,
        activity: activity,
      ));
    } catch (_) {
      if (_closed || seq != _seq) {
        return;
      }
      // Deliberately payload-free: a ledger failure never surfaces internal
      // detail in state.
      _emit(const KarmaState.error(
          'Could not load your karma. Please try again.'));
    }
  }

  @override
  Future<bool> record(KarmaAction action) async {
    if (_closed) {
      return false;
    }
    final seq = ++_seq;
    try {
      // The local actor is this device's blind-hash identity; the production
      // wiring passes the shared hash (harness seeds it). A rejected record
      // (malformed actor) or a missing identity degrades to the generic
      // error state and returns false.
      final actorHash = await _localActorHash();
      if (_closed || seq != _seq) {
        return false;
      }
      await _repository.record(action: action, actorHash: actorHash);
      await refresh();
      return true;
    } catch (_) {
      if (_closed || seq != _seq) {
        return false;
      }
      _emit(const KarmaState.error(
          'Could not record your karma. Please try again.'));
      return false;
    }
  }

  /// The local actor's 64-hex blind hash. Production wiring supplies the
  /// shared identity hash; tests inject a fixed hash. A missing actor
  /// (no identity yet) makes [record] reject the action cleanly.
  final Future<String> Function() localActorHash;

  static Future<String> _throwMissingActor() async =>
      throw StateError('No local blind-hash identity configured');

  /// Returns the local 64-hex blind-hash actor (or throws when absent).
  Future<String> _localActorHash() async => localActorHash();

  List<KarmaActivity> _projectActivity(List<KarmaEvent> events) {
    final rows = events.reversed
        .take(maxActivityRows)
        .map((e) => KarmaActivity(
              action: e.action,
              delta: e.delta,
              at: e.at,
            ))
        .toList();
    return List.unmodifiable(rows);
  }

  void _emit(KarmaState state) {
    _current = state;
    _controller.add(state);
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _controller.close();
  }
}
