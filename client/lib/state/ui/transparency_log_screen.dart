import 'package:flutter/material.dart';

import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../../transparency/domain/transparency_action.dart';
import '../../transparency/domain/transparency_record.dart';
import '../domain/transparency_log_bloc.dart';
import '../domain/transparency_log_state.dart';
import 'ledger_theme.dart';

/// The transparency log screen (Task 10.5 — Transparency Log).
///
/// Renders the append-only audit trail for a pin-code board, including
/// the integrity verification status, record count, and the full list
/// of public audit records with fixed action labels and timestamps.
///
/// SECURITY CHECKPOINT (10.5): the screen renders ONLY the public-label
/// summaries, fixed action labels, integer counts, and timestamps.
/// No blind hash, no phone number, no identity, no token ever appears
/// in the widget tree. Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class TransparencyLogScreen extends StatefulWidget {
  /// The transparency log BLoC (injected — never constructed here).
  final TransparencyLogBloc bloc;

  /// Injectable FLAG_SECURE service (test seam).
  final SecureFlagService? secureFlagService;

  const TransparencyLogScreen({
    super.key,
    required this.bloc,
    this.secureFlagService,
  });

  @override
  State<TransparencyLogScreen> createState() => _TransparencyLogScreenState();
}

class _TransparencyLogScreenState extends State<TransparencyLogScreen> {
  TransparencyLogState? _last;

  @override
  void initState() {
    super.initState();
    _last = widget.bloc.current;
    widget.bloc.state.listen((state) {
      if (!mounted) return;
      setState(() => _last = state);
    });
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
    final state = _last ?? const TransparencyLogState();

    return _secure(Scaffold(
      backgroundColor: LedgerTheme.paper,
      appBar: AppBar(
        title: const Text('Transparency Log'),
        backgroundColor: LedgerTheme.ink,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.verified_user),
            tooltip: 'Verify integrity',
            onPressed: () => widget.bloc.verifyIntegrity(),
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Integrity status banner ---
          _buildIntegrityBanner(state),
          // --- Record count ---
          _buildRecordCount(state),
          // --- Record list ---
          Expanded(
            child: state.records.isEmpty
                ? _buildEmptyState()
                : _buildRecordList(state),
          ),
        ],
      ),
    ));
  }

  Widget _buildIntegrityBanner(TransparencyLogState state) {
    final isValid = state.integrityValid;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isValid
          ? LedgerTheme.verifiedEmerald.withAlpha(30)
          : LedgerTheme.alertRed.withAlpha(30),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.verified : Icons.error,
            color: isValid ? LedgerTheme.verifiedEmerald : LedgerTheme.alertRed,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isValid ? 'Chain integrity verified' : 'Integrity check failed',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color:
                  isValid ? LedgerTheme.verifiedEmerald : LedgerTheme.alertRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCount(TransparencyLogState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '${state.recordCount} record${state.recordCount == 1 ? '' : 's'}',
        style: TextStyle(
          fontSize: 12,
          color: LedgerTheme.ink.withAlpha(120),
        ),
      ),
    );
  }

  Widget _buildRecordList(TransparencyLogState state) {
    return ListView.builder(
      itemCount: state.records.length,
      itemBuilder: (context, index) {
        final record = state.records[index];
        return _RecordTile(record: record);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long,
            size: 64,
            color: LedgerTheme.ink.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            'No transparency records',
            style: TextStyle(
              fontSize: 16,
              color: LedgerTheme.ink.withAlpha(120),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single transparency record tile.
class _RecordTile extends StatelessWidget {
  final TransparencyRecord record;

  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _actionIcon(record.action),
      title: Text(
        record.summary,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '${record.action.shortLabel} · ${_formatTime(record.occurredAt)}',
        style: TextStyle(
          fontSize: 12,
          color: LedgerTheme.ink.withAlpha(120),
        ),
      ),
      trailing: Text(
        '#${record.seq}',
        style: TextStyle(
          fontSize: 11,
          color: LedgerTheme.ink.withAlpha(80),
        ),
      ),
    );
  }

  Widget _actionIcon(TransparencyAction action) {
    switch (action) {
      case TransparencyAction.moderationAction:
        return const Icon(Icons.gavel, color: LedgerTheme.alertRed);
      case TransparencyAction.contentReview:
        return const Icon(Icons.fact_check, color: LedgerTheme.verifiedEmerald);
      case TransparencyAction.accessRequest:
        return const Icon(Icons.key, color: LedgerTheme.civicGold);
      case TransparencyAction.dataExport:
        return const Icon(Icons.download, color: LedgerTheme.ink);
      case TransparencyAction.accountAction:
        return const Icon(Icons.person, color: LedgerTheme.academyTeal);
      case TransparencyAction.systemEvent:
        return const Icon(Icons.settings, color: LedgerTheme.muted);
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
