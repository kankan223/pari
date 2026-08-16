import 'dart:async';

import 'package:flutter/material.dart';

import '../../ledger/domain/ledger_category.dart';
import '../domain/ledger_compose_bloc.dart';
import '../domain/ledger_compose_state.dart';
import 'ledger_theme.dart';

/// The Daily Ledger compose post screen (DESIGN.md §7.3).
///
/// Collects Category * / Pin Code * / Headline * / Details via the
/// [LedgerComposeBloc] (state only — no repository access in the widget
/// tree). The `Publish — send to review` action submits the draft to the
/// offline-first queue; the karma-messaging row is a static, non-alarming
/// status line (Peer Review Gate for Contributor tier).
///
/// SECURITY CHECKPOINT (Task 7.1): the form handles only civic content
/// (category, pin code, headline, body) — no identity, no PII. The draft is
/// persisted sealed (encrypted at rest) by the queue layer.
class LedgerComposeScreen extends StatefulWidget {
  const LedgerComposeScreen({
    super.key,
    required this.bloc,
    required this.defaultPinCode,
    this.onCancel,
    this.onSubmitted,
  });

  final LedgerComposeBloc bloc;

  /// Pre-filled pin code (the user's registered scope, FR-L2 default).
  final String defaultPinCode;

  final VoidCallback? onCancel;

  /// Fired when the draft is successfully queued — the caller pops/confirms.
  final VoidCallback? onSubmitted;

  @override
  State<LedgerComposeScreen> createState() => _LedgerComposeScreenState();
}

class _LedgerComposeScreenState extends State<LedgerComposeScreen> {
  final _headlineController = TextEditingController();
  final _bodyController = TextEditingController();
  final _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pinController.text = widget.defaultPinCode;
    unawaited(widget.bloc.start());
    unawaited(widget.bloc.setPinCode(widget.defaultPinCode));
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _bodyController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LedgerTheme.paper,
      appBar: AppBar(
        backgroundColor: LedgerTheme.paper,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
          onPressed: widget.onCancel ?? () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'New Post',
          style: TextStyle(
            fontFamily: 'serif',
            fontWeight: FontWeight.w700,
            color: LedgerTheme.ink,
          ),
        ),
        actions: const [
          // Preview lands with the composer polish task.
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Preview',
                style: TextStyle(color: LedgerTheme.ledgerGreen, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<LedgerComposeState>(
        stream: widget.bloc.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? const LedgerComposeState();
          return _buildForm(context, state);
        },
      ),
    );
  }

  /// Submits the draft and fires [LedgerComposeScreen.onSubmitted] only
  /// when the queue persisted it successfully.
  Future<void> _submit() async {
    await widget.bloc.submit();
    if (!mounted) return;
    if (widget.bloc.current.isSubmitted && widget.onSubmitted != null) {
      widget.onSubmitted!();
    }
  }

  Widget _buildForm(BuildContext context, LedgerComposeState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _FieldLabel('Category *'),
        const SizedBox(height: 6),
        _CategoryDropdown(
          selected: state.category,
          onSelected: (c) => unawaited(widget.bloc.setCategory(c)),
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Pin Code *'),
        const SizedBox(height: 6),
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(fontSize: 15),
          decoration: const InputDecoration(
            hintText: '6-digit pin code',
            counterText: '',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => unawaited(widget.bloc.setPinCode(v)),
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Headline *'),
        const SizedBox(height: 6),
        TextField(
          controller: _headlineController,
          maxLength: 120,
          style: const TextStyle(fontSize: 15),
          decoration: const InputDecoration(
            hintText: 'State the issue plainly',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => unawaited(widget.bloc.setHeadline(v)),
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Details'),
        const SizedBox(height: 6),
        TextField(
          controller: _bodyController,
          maxLines: 5,
          maxLength: 2000,
          style: const TextStyle(fontSize: 15, height: 1.4),
          decoration: const InputDecoration(
            hintText: 'What happened, when, and what evidence you have',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => unawaited(widget.bloc.setBody(v)),
        ),
        const SizedBox(height: 10),
        // Evidence row — media attachment lands with the upload task.
        const Row(
          children: [
            _EvidenceChip(icon: Icons.photo_outlined, label: 'Add photo'),
            SizedBox(width: 8),
            _EvidenceChip(
                icon: Icons.attach_file_rounded, label: 'Add document'),
            SizedBox(width: 8),
            _EvidenceChip(icon: Icons.mic_none_rounded, label: 'Voice note'),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: LedgerTheme.ledgerGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 16, color: LedgerTheme.ledgerGreen),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your karma tier is Contributor. This post goes to '
                  'Peer Review Gate before publishing.',
                  style: TextStyle(color: LedgerTheme.ink, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        if (state.hasError) ...[
          const SizedBox(height: 12),
          const Text(
            'Please add a category, a valid 6-digit pin code, and a '
            'headline before publishing.',
            style: TextStyle(color: LedgerTheme.alertRed, fontSize: 12),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: state.status == LedgerComposeStatus.submitting
                ? null
                : () => unawaited(_submit()),
            style: FilledButton.styleFrom(
              backgroundColor: LedgerTheme.ledgerGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: state.status == LedgerComposeStatus.submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Publish — send to review'),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: LedgerTheme.ink,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({required this.selected, required this.onSelected});

  final LedgerCategory? selected;
  final ValueChanged<LedgerCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<LedgerCategory>(
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      hint: const Text('# CHOOSE CATEGORY'),
      items: [
        for (final category in LedgerCategory.values)
          DropdownMenuItem(
            value: category,
            child:
                Text(category.fullName, style: const TextStyle(fontSize: 14)),
          ),
      ],
      onChanged: (value) => onSelected(value),
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: LedgerTheme.divider),
        borderRadius: BorderRadius.circular(4),
        color: LedgerTheme.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: LedgerTheme.muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: LedgerTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
