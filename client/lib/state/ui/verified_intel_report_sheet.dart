import 'package:flutter/material.dart';

import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../../war_room/domain/custody_log.dart';
import '../domain/war_room_bloc.dart';
import 'war_room_theme.dart';

/// The Verified Intel Report viewer (Task 8.6 — wired in from the Task 8.1
/// placeholder slot).
///
/// On open the bloc signs the case's deterministic report (HMAC-SHA256 via
/// the device-held key) and this sheet renders the report text + its
/// signature with a VERIFIED badge, plus the legal-aid handoff action.
///
/// SECURITY CHECKPOINT (8.6): the sheet renders ONLY the non-PII report
/// attributes (stamp, severity, SLA, analyst count, filed date, stage) and
/// the opaque HMAC signature. No narrative, no evidence bytes, no identity.
/// Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class VerifiedIntelReportSheet extends StatefulWidget {
  final WarRoomBloc bloc;
  final String caseNumber;
  final SecureFlagService? secureFlagService;

  const VerifiedIntelReportSheet({
    super.key,
    required this.bloc,
    required this.caseNumber,
    this.secureFlagService,
  });

  @override
  State<VerifiedIntelReportSheet> createState() =>
      _VerifiedIntelReportSheetState();
}

class _VerifiedIntelReportSheetState extends State<VerifiedIntelReportSheet> {
  late final Future<SignedReport> _signing =
      widget.bloc.signVerifiedReport(widget.caseNumber);

  bool _handoffQueued = false;
  String? _handoffId;

  Future<void> _queueHandoff() async {
    final id = await widget.bloc.queueLegalAidHandoff(widget.caseNumber);
    if (!mounted) {
      return;
    }
    setState(() {
      _handoffQueued = true;
      _handoffId = id;
    });
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return _secure(
      SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'VERIFIED INTEL REPORT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFamily: WarRoomTheme.monoFont,
                letterSpacing: 1.4,
                color: WarRoomTheme.muted,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<SignedReport>(
              future: _signing,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return const Text(
                    'The report could not be generated.',
                    style: TextStyle(fontSize: 13, color: WarRoomTheme.muted),
                  );
                }
                final signed = snapshot.data!;
                final report = signed.report;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ReportCard(report: report),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(Icons.verified,
                            size: 16, color: Color(0xFF1E6B3A)),
                        SizedBox(width: 6),
                        Text(
                          'VERIFIED · HMAC-SHA256 SIGNED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: WarRoomTheme.monoFont,
                            letterSpacing: 0.8,
                            color: Color(0xFF1E6B3A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _SignatureBox(signature: signed.signature),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _handoffQueued ? null : _queueHandoff,
                style: FilledButton.styleFrom(
                  backgroundColor: WarRoomTheme.amber,
                  disabledBackgroundColor: WarRoomTheme.divider,
                ),
                icon: const Icon(Icons.outgoing_mail, size: 18),
                label: Text(
                  _handoffQueued
                      ? 'HANDOFF QUEUED'
                      : 'Send to legal aid (encrypted handoff)',
                ),
              ),
            ),
            if (_handoffQueued && _handoffId != null) ...[
              const SizedBox(height: 8),
              Text(
                'Handoff $_handoffId queued for secure delivery.',
                style: const TextStyle(
                  fontSize: 12,
                  color: WarRoomTheme.muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final VerifiedIntelReport report;

  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WarRoomTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WarRoomTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.canonicalText(),
            style: const TextStyle(
              fontSize: 11,
              fontFamily: WarRoomTheme.monoFont,
              height: 1.6,
              color: WarRoomTheme.dossierInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignatureBox extends StatelessWidget {
  final String signature;

  const _SignatureBox({required this.signature});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF1E6B3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HMAC SIGNATURE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              fontFamily: WarRoomTheme.monoFont,
              letterSpacing: 0.8,
              color: WarRoomTheme.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            signature,
            style: const TextStyle(
              fontSize: 10,
              fontFamily: WarRoomTheme.monoFont,
              color: WarRoomTheme.dossierInk,
            ),
          ),
        ],
      ),
    );
  }
}
