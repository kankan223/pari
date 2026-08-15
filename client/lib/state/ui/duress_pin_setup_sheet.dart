import 'dart:async';

import 'package:flutter/material.dart';

import '../../security/domain/root_detection_service.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/duress_setup_bloc.dart';
import '../domain/duress_setup_state.dart';
import 'vault_theme.dart';

/// Duress PIN setup sheet (Task 6.6 onboarding).
///
/// The ONE screen that labels the two PINs (the user is choosing them).
/// After this screen completes, no component in the app persists, logs, or
/// exposes which PIN is real vs duress — the unlock flow and the vault
/// files treat both identically.
///
/// SECURITY CHECKPOINT (Task 6.6):
/// - Both fields are obscured; the PINs are never persisted or logged.
/// - Failure shows a GENERIC message — identical PINs, already-registered,
///   or storage errors are never distinguished to the UI.
/// - Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class DuressPinSetupSheet extends StatefulWidget {
  const DuressPinSetupSheet({
    super.key,
    required this.bloc,
    required this.onRegistered,
    this.secureFlagService,
    this.rootDetectionService,
  });

  final DuressSetupBloc bloc;

  /// Called after both PINs are registered successfully.
  final VoidCallback onRegistered;
  final SecureFlagService? secureFlagService;
  final RootDetectionService? rootDetectionService;

  /// Opens the sheet as a modal bottom sheet. Returns true when the PINs
  /// were registered.
  static Future<bool> show(
    BuildContext context, {
    required DuressSetupBloc bloc,
    required VoidCallback onRegistered,
    SecureFlagService? secureFlagService,
    RootDetectionService? rootDetectionService,
  }) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => DuressPinSetupSheet(
        bloc: bloc,
        onRegistered: onRegistered,
        secureFlagService: secureFlagService,
        rootDetectionService: rootDetectionService,
      ),
    );
    return done ?? false;
  }

  @override
  State<DuressPinSetupSheet> createState() => _DuressPinSetupSheetState();
}

class _DuressPinSetupSheetState extends State<DuressPinSetupSheet> {
  final TextEditingController _realPin = TextEditingController();
  final TextEditingController _duressPin = TextEditingController();
  bool _submitting = false;
  bool _hasError = false;
  StreamSubscription<DuressSetupState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.bloc.state.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() => _hasError = state.hasError);
      if (state.phase == DuressSetupPhase.registered) {
        Navigator.of(context).pop(true);
        widget.onRegistered();
      }
    });
    unawaited(widget.bloc.start());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _realPin.dispose();
    _duressPin.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _hasError = false;
    });
    await widget.bloc.register(
      realPin: _realPin.text,
      duressPin: _duressPin.text,
    );
    // Wipe the in-memory PIN copies from the controllers on every attempt.
    _realPin.clear();
    _duressPin.clear();
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _secure(
      SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'SET UP VAULT PINs',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: VaultTheme.vaultBlue,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose a real PIN and a separate duress PIN. Under duress, '
                'entering the duress PIN opens a decoy vault that looks '
                'identical to the real one.',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _realPin,
                obscureText: true,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Real PIN',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _duressPin,
                obscureText: true,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_register()),
                decoration: InputDecoration(
                  labelText: 'Duress PIN',
                  prefixIcon: const Icon(Icons.warning_amber_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: _submitting ? null : () => unawaited(_register()),
                  style: FilledButton.styleFrom(
                    backgroundColor: VaultTheme.vaultBlue,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Register PINs'),
                ),
              ),
              if (_hasError) ...[
                const SizedBox(height: 12),
                const Text(
                  'PINs could not be registered. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Wraps in [SecureScreenWrapper] (FLAG_SECURE), mirroring every Vault
  /// screen (Task 6.1 convention).
  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    final rootDetectionService = widget.rootDetectionService;
    return flag == null
        ? SecureScreenWrapper(
            rootDetectionService: rootDetectionService, child: child)
        : SecureScreenWrapper(
            secureFlagService: flag,
            rootDetectionService: rootDetectionService,
            child: child,
          );
  }
}
