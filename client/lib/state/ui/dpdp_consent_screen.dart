import 'package:flutter/material.dart';

import '../../consent/domain/consent_type.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/consent_bloc.dart';
import '../domain/consent_state.dart';
import 'ledger_theme.dart';

/// The DPDP consent screen (Task 11.1 — DPDP Consent Implementation).
///
/// Renders the Digital Personal Data Protection Act consent flow,
/// listing all data processing purposes with toggle switches. Users
/// must grant all required consents before using the platform.
///
/// SECURITY CHECKPOINT (11.1): the screen renders only fixed consent
/// type labels and boolean toggle states. No phone number, no blind
/// hash, no identity, no token ever appears in the widget tree.
/// Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class DpdpConsentScreen extends StatefulWidget {
  /// The consent BLoC (injected — never constructed here).
  final ConsentBloc bloc;

  /// Injectable FLAG_SECURE service (test seam).
  final SecureFlagService? secureFlagService;

  /// Host seam: called when all required consents are granted.
  final VoidCallback? onConsentComplete;

  /// Host seam: called when user requests data deletion.
  final VoidCallback? onDataDeleted;

  const DpdpConsentScreen({
    super.key,
    required this.bloc,
    this.secureFlagService,
    this.onConsentComplete,
    this.onDataDeleted,
  });

  @override
  State<DpdpConsentScreen> createState() => _DpdpConsentScreenState();
}

class _DpdpConsentScreenState extends State<DpdpConsentScreen> {
  ConsentState? _last;

  @override
  void initState() {
    super.initState();
    _last = widget.bloc.current;
    widget.bloc.state.listen((state) {
      if (!mounted) return;
      setState(() => _last = state);
      // Check if all consents just became granted.
      if (state.allRequiredGranted &&
          state.phase == ConsentPhase.ready &&
          widget.onConsentComplete != null) {
        widget.onConsentComplete!();
      }
      // Check if data deletion completed.
      if (state.phase == ConsentPhase.deleted && widget.onDataDeleted != null) {
        widget.onDataDeleted!();
      }
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
    final state = _last ?? const ConsentState();

    return _secure(Scaffold(
      backgroundColor: LedgerTheme.paper,
      appBar: AppBar(
        title: const Text('Data Protection Consent'),
        backgroundColor: LedgerTheme.ink,
        foregroundColor: Colors.white,
      ),
      body: state.phase == ConsentPhase.loading
          ? const Center(child: CircularProgressIndicator())
          : state.phase == ConsentPhase.deleting
              ? _buildDeletingState()
              : state.phase == ConsentPhase.deleted
                  ? _buildDeletedState()
                  : _buildConsentForm(state),
    ));
  }

  Widget _buildConsentForm(ConsentState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header
        const Text(
          'DIGITAL PERSONAL DATA PROTECTION',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: LedgerTheme.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Version ${state.consentVersion}',
          style: TextStyle(
            fontSize: 12,
            color: LedgerTheme.ink.withAlpha(120),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Under India\'s Digital Personal Data Protection Act (DPDP), '
          'we need your consent before processing your personal data. '
          'Please review each purpose below.',
          style: TextStyle(
            fontSize: 13,
            color: LedgerTheme.ink.withAlpha(180),
          ),
        ),
        const SizedBox(height: 20),

        // Consent toggles
        ...ConsentType.values.map((type) => _ConsentTile(
              type: type,
              granted: state.hasConsent(type),
              required: type != ConsentType.analytics,
              onChanged: (granted) {
                if (granted) {
                  widget.bloc.grantAll();
                } else {
                  widget.bloc.withdrawConsent(type);
                }
              },
            )),

        const SizedBox(height: 20),

        // Status banner
        if (state.allRequiredGranted)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LedgerTheme.verifiedEmerald.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle,
                    color: LedgerTheme.verifiedEmerald, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All required consents granted. You may proceed.',
                    style: TextStyle(
                      fontSize: 13,
                      color: LedgerTheme.verifiedEmerald,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // Withdrawal section
        if (state.allRequiredGranted)
          TextButton(
            onPressed: () => _showWithdrawalDialog(),
            child: const Text(
              'Withdraw All Consents',
              style: TextStyle(color: LedgerTheme.alertRed),
            ),
          ),

        const SizedBox(height: 8),
        Text(
          'You may withdraw consent at any time. Withdrawal will '
          'trigger deletion of your personal data as required by DPDP §8.',
          style: TextStyle(
            fontSize: 11,
            color: LedgerTheme.ink.withAlpha(120),
          ),
        ),
      ],
    );
  }

  Widget _buildDeletingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Deleting your data...',
            style: TextStyle(
              fontSize: 14,
              color: LedgerTheme.ink.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeletedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_forever, size: 64, color: LedgerTheme.alertRed),
            const SizedBox(height: 16),
            const Text(
              'Your data has been deleted',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: LedgerTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'All personal data has been removed as per your consent '
              'withdrawal request. You may re-consent at any time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: LedgerTheme.ink.withAlpha(180),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWithdrawalDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw All Consents?'),
        content: const Text(
          'This will remove all your personal data from the platform '
          'as required by India\'s DPDP Act. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.bloc.withdrawAll();
            },
            child: const Text(
              'Withdraw & Delete',
              style: TextStyle(color: LedgerTheme.alertRed),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single consent toggle tile.
class _ConsentTile extends StatelessWidget {
  final ConsentType type;
  final bool granted;
  final bool required;
  final ValueChanged<bool> onChanged;

  const _ConsentTile({
    required this.type,
    required this.granted,
    required this.required,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: SwitchListTile(
        title: Text(
          type.label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              type.description,
              style: TextStyle(
                fontSize: 12,
                color: LedgerTheme.ink.withAlpha(150),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              required ? 'Required' : 'Optional',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: required ? LedgerTheme.alertRed : LedgerTheme.muted,
              ),
            ),
          ],
        ),
        value: granted,
        onChanged: onChanged,
        activeThumbColor: LedgerTheme.verifiedEmerald,
      ),
    );
  }
}
