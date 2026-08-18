import 'package:flutter/material.dart';

import '../../karma/domain/karma_gate.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/karma_bloc.dart';
import '../domain/karma_state.dart';
import 'ledger_theme.dart';

/// The karma status screen (Task 10.2 — Civic Karma Engine).
///
/// Renders the PUBLIC karma balance, the deterministic tier band
/// (DESIGN.md §4.3), the per-gate privilege checklist (PRD §9.2), and the
/// recent activity feed. The gate checklist is the client-side projection
/// of the karma engine — the server enforces the gates on the wire; the
/// client shows exactly which privileges the local score unlocks.
///
/// SECURITY CHECKPOINT (10.2): the screen renders ONLY the public integer
/// balance + the fixed tier label + the fixed gate labels + the fixed
/// activity labels with deltas and timestamps. No blind hash, no event id,
/// no identity fragment, no payload ever appears in the widget tree.
/// Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class KarmaStatusScreen extends StatefulWidget {
  /// The karma BLoC (injected — never constructed here).
  final KarmaBloc bloc;

  /// Injectable FLAG_SECURE service (test seam) — null uses the production
  /// default.
  final SecureFlagService? secureFlagService;

  const KarmaStatusScreen({
    super.key,
    required this.bloc,
    this.secureFlagService,
  });

  @override
  State<KarmaStatusScreen> createState() => _KarmaStatusScreenState();
}

class _KarmaStatusScreenState extends State<KarmaStatusScreen> {
  KarmaState? _last;

  @override
  void initState() {
    super.initState();
    _last = widget.bloc.current;
    widget.bloc.state.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() => _last = state);
    });
    // Load the ledger on mount.
    widget.bloc.refresh();
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final state = _last ?? const KarmaState.idle();
    return _secure(Scaffold(
      backgroundColor: LedgerTheme.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _masthead(),
            Expanded(child: _body(state)),
          ],
        ),
      ),
    ));
  }

  Widget _masthead() => Container(
        color: LedgerTheme.ink,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: const Row(
          children: [
            Text(
              '❧ CIVIC COMMONS',
              style: TextStyle(
                color: LedgerTheme.paper,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            Spacer(),
            Text(
              'KARMA',
              style: TextStyle(
                color: LedgerTheme.civicGold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      );

  Widget _body(KarmaState state) {
    if (state.isLoading) {
      return const Center(
          child:
              CircularProgressIndicator()); // ignore: prefer_const_constructors
    }
    if (state.isError) {
      return _message(state.errorMessage ?? 'Karma unavailable.');
    }
    if (!state.isReady) {
      return _message('Karma is loading…');
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _balanceCard(state),
        const SizedBox(height: 16),
        _gatesCard(state),
        const SizedBox(height: 16),
        _activityCard(state),
      ],
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: LedgerTheme.muted, fontSize: 14),
          ),
        ),
      );

  Widget _balanceCard(KarmaState state) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: LedgerTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: LedgerTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'KARMA BALANCE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: LedgerTheme.muted,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${state.balance}',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: LedgerTheme.civicGold,
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${state.tier.label} tier',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: LedgerTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Earned by verified contributions across the Ledger, '
              'War Room, and Academy. Decays 2% per inactive month.',
              style: TextStyle(fontSize: 12, color: LedgerTheme.muted),
            ),
          ],
        ),
      );

  Widget _gatesCard(KarmaState state) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: LedgerTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: LedgerTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PRIVILEGES UNLOCKED BY KARMA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: LedgerTheme.muted,
              ),
            ),
            const SizedBox(height: 12),
            for (final gate in KarmaGate.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      state.satisfied(gate)
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: state.satisfied(gate)
                          ? LedgerTheme.verifiedEmerald
                          : LedgerTheme.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        gate.label,
                        style: const TextStyle(
                            fontSize: 13, color: LedgerTheme.ink),
                      ),
                    ),
                    Text(
                      '${gate.threshold}+',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: LedgerTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _activityCard(KarmaState state) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: LedgerTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: LedgerTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RECENT KARMA ACTIVITY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: LedgerTheme.muted,
              ),
            ),
            const SizedBox(height: 8),
            if (state.activity.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No karma events yet.',
                  style: TextStyle(fontSize: 13, color: LedgerTheme.muted),
                ),
              )
            else
              for (final row in state.activity)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        row.delta >= 0
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                        size: 16,
                        color: row.delta >= 0
                            ? LedgerTheme.verifiedEmerald
                            : LedgerTheme.alertRed,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row.action.label,
                          style: const TextStyle(
                              fontSize: 13, color: LedgerTheme.ink),
                        ),
                      ),
                      Text(
                        '${row.delta >= 0 ? '+' : ''}${row.delta}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: row.delta >= 0
                              ? LedgerTheme.verifiedEmerald
                              : LedgerTheme.alertRed,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      );
}
