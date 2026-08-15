import 'dart:async';

import 'package:flutter/material.dart';

import '../../duress/domain/duress_service.dart';
import '../../security/domain/root_detection_service.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/vault_unlock_bloc.dart';
import '../domain/vault_unlock_state.dart';
import 'vault_masthead.dart';
import 'vault_theme.dart';

/// The Vault unlock screen (Task 6.6).
///
/// A single PIN prompt — the REAL and DURESS PINs are entered through
/// exactly the same UI, with identical transitions and identical error
/// presentation. The opened vault (real or decoy) is delivered ONLY to
/// the [onUnlocked] callback (the composition root routes the UI from
/// there); this screen never learns, renders, or reveals which vault was
/// opened, and never displays any PIN.
///
/// SECURITY CHECKPOINT (Task 6.6):
/// - The duress PIN is indistinguishable from the real PIN — same widget,
///   same flow, same generic error for any failure.
/// - The PIN field is obscured; the PIN is never persisted or logged.
/// - The screen is wrapped in [SecureScreenWrapper] (FLAG_SECURE).
/// - When no vaults are registered, the screen offers the setup path
///   (onboarding) instead of a dead PIN prompt.
class VaultUnlockScreen extends StatefulWidget {
  const VaultUnlockScreen({
    super.key,
    required this.bloc,
    required this.onUnlocked,
    this.onSetupRequired,
    this.secureFlagService,
    this.rootDetectionService,
  });

  final VaultUnlockBloc bloc;

  /// Routing seam: called with the opened [UnlockResult] (real or decoy).
  /// The caller decides which UI to show — never this screen.
  final ValueChanged<UnlockResult> onUnlocked;

  /// Opens the duress PIN setup flow (shown when no vaults are registered).
  final VoidCallback? onSetupRequired;
  final SecureFlagService? secureFlagService;
  final RootDetectionService? rootDetectionService;

  @override
  State<VaultUnlockScreen> createState() => _VaultUnlockScreenState();
}

class _VaultUnlockScreenState extends State<VaultUnlockScreen> {
  final TextEditingController _pin = TextEditingController();
  VaultUnlockState? _state;
  bool _submitting = false;
  StreamSubscription<VaultUnlockState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.bloc.state.listen((state) {
      if (mounted) {
        setState(() => _state = state);
      }
    });
    unawaited(widget.bloc.start());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    final result = await widget.bloc.unlock(_pin.text);
    // Wipe the in-memory PIN copy from the controller on every attempt.
    _pin.clear();
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (result != null) {
      widget.onUnlocked(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final isRegistered = state?.isRegistered ?? false;
    final isUnlocking =
        state?.phase == VaultUnlockPhase.unlocking || _submitting;
    final showError = state?.hasError ?? false;
    return _secure(
      Scaffold(
        body: Column(
          children: [
            const VaultMasthead(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    const Icon(Icons.lock_rounded,
                        size: 40, color: VaultTheme.vaultBlue),
                    const SizedBox(height: 12),
                    Text(
                      isRegistered ? 'ENTER PIN' : 'VAULT LOCK',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: VaultTheme.vaultBlue,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isRegistered
                          ? 'Enter your PIN to open the vault.'
                          : 'Set up your vault PINs to begin.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    if (isRegistered) ...[
                      TextField(
                        controller: _pin,
                        obscureText: true,
                        enabled: !isUnlocking,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => unawaited(_unlock()),
                        decoration: InputDecoration(
                          hintText: 'PIN',
                          prefixIcon: const Icon(Icons.pin_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 46,
                        child: FilledButton(
                          onPressed:
                              isUnlocking ? null : () => unawaited(_unlock()),
                          style: FilledButton.styleFrom(
                            backgroundColor: VaultTheme.vaultBlue,
                          ),
                          child: isUnlocking
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Unlock'),
                        ),
                      ),
                      if (showError) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Incorrect PIN. Please try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ] else ...[
                      SizedBox(
                        height: 46,
                        child: FilledButton(
                          onPressed: widget.onSetupRequired,
                          style: FilledButton.styleFrom(
                            backgroundColor: VaultTheme.vaultBlue,
                          ),
                          child: const Text('Set up PINs'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
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
