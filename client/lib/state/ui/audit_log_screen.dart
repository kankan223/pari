import 'package:flutter/material.dart';

import '../../audit/domain/audit_record.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/audit_log_bloc.dart';
import '../domain/audit_log_state.dart';
import 'ledger_theme.dart';

/// The Audit Log viewer screen (Task 11.2 — Audit Logging System).
///
/// Renders the append-only, tamper-evident audit trail with an integrity
/// status banner, record count, and a list of audit events.
///
/// SECURITY CHECKPOINT (11.2): the screen renders only fixed action labels
/// and public-label summaries. No phone number, no blind hash, no identity,
/// no token ever appears in the widget tree.
/// Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class AuditLogScreen extends StatefulWidget {
  /// The audit log BLoC (injected — never constructed here).
  final AuditLogBloc bloc;

  /// Injectable FLAG_SECURE service (test seam).
  final SecureFlagService? secureFlagService;

  const AuditLogScreen({
    super.key,
    required this.bloc,
    this.secureFlagService,
  });

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  AuditLogState? _last;

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
    final state = _last ?? const AuditLogState();

    return _secure(Scaffold(
      backgroundColor: LedgerTheme.paper,
      appBar: AppBar(
        title: const Text('Audit Log'),
        backgroundColor: LedgerTheme.ink,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.verified, size: 20),
            tooltip: 'Verify Integrity',
            onPressed: () => widget.bloc.verifyIntegrity(),
          ),
        ],
      ),
      body: state.phase == AuditLogPhase.loading
          ? const Center(child: CircularProgressIndicator())
          : state.phase == AuditLogPhase.error
              ? _buildErrorState(state)
              : _buildLogView(state),
    ));
  }

  Widget _buildErrorState(AuditLogState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: LedgerTheme.alertRed),
            const SizedBox(height: 16),
            Text(
              state.errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: LedgerTheme.ink.withAlpha(180),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogView(AuditLogState state) {
    return Column(
      children: [
        // Integrity status banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: state.integrityValid
              ? LedgerTheme.verifiedEmerald.withAlpha(30)
              : LedgerTheme.alertRed.withAlpha(30),
          child: Row(
            children: [
              Icon(
                state.integrityValid ? Icons.verified : Icons.broken_image,
                size: 18,
                color: state.integrityValid
                    ? LedgerTheme.verifiedEmerald
                    : LedgerTheme.alertRed,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.integrityValid
                      ? 'Chain integrity verified — ${state.recordCount} record(s)'
                      : 'Chain integrity FAILED — possible tampering detected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: state.integrityValid
                        ? LedgerTheme.verifiedEmerald
                        : LedgerTheme.alertRed,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Record list
        Expanded(
          child: state.records.isEmpty
              ? Center(
                  child: Text(
                    'No audit records yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: LedgerTheme.ink.withAlpha(120),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.records.length,
                  itemBuilder: (context, index) {
                    final record = state.records[index];
                    return _AuditRecordTile(record: record);
                  },
                ),
        ),
      ],
    );
  }
}

/// A single audit record tile.
class _AuditRecordTile extends StatelessWidget {
  final AuditRecord record;

  const _AuditRecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: LedgerTheme.ink.withAlpha(20),
          child: Text(
            record.action.shortLabel.substring(0, 1),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: LedgerTheme.ink,
            ),
          ),
        ),
        title: Text(
          record.action.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          record.summary,
          style: TextStyle(
            fontSize: 12,
            color: LedgerTheme.ink.withAlpha(150),
          ),
        ),
        trailing: Text(
          '#${record.seq}',
          style: TextStyle(
            fontSize: 11,
            color: LedgerTheme.ink.withAlpha(100),
          ),
        ),
      ),
    );
  }
}
