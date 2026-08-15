import 'dart:async';

import 'package:flutter/material.dart';

import '../../security/domain/root_detection_service.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/device_pairing_bloc.dart';
import '../domain/device_pairing_state.dart';
import 'vault_theme.dart';

/// Pairing-code entry sheet for the NEW device (Task 6.5).
///
/// The camera-based [QrScanner] is wired by the caller; this sheet provides
/// the manual-entry path (enter the code shown by the primary device) so the
/// flow works without a camera and is fully testable. The entered text is
/// passed to [DevicePairingBloc.authorizeCode] — the BLoC/service strictly
/// validate it, so a bad or PII-shaped code can never pair.
///
/// SECURITY CHECKPOINT (Task 6.5): the sheet is wrapped in
/// [SecureScreenWrapper] (FLAG_SECURE) and renders only fixed labels + the
/// entered text field (which is code input, not displayed output). It never
/// shows blind hashes, key material, or payload content as output.
class PairingScanSheet extends StatefulWidget {
  final DevicePairingBloc pairingBloc;
  final SecureFlagService? secureFlagService;
  final RootDetectionService? rootDetectionService;

  const PairingScanSheet({
    super.key,
    required this.pairingBloc,
    this.secureFlagService,
    this.rootDetectionService,
  });

  /// Opens the sheet as a modal bottom sheet. Returns true when the code was
  /// authorized successfully (the pairing completed).
  static Future<bool> show(
    BuildContext context, {
    required DevicePairingBloc pairingBloc,
    SecureFlagService? secureFlagService,
    RootDetectionService? rootDetectionService,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => PairingScanSheet(
        pairingBloc: pairingBloc,
        secureFlagService: secureFlagService,
        rootDetectionService: rootDetectionService,
      ),
    );
    return ok ?? false;
  }

  @override
  State<PairingScanSheet> createState() => _PairingScanSheetState();
}

class _PairingScanSheetState extends State<PairingScanSheet> {
  final TextEditingController _controller = TextEditingController();
  StreamSubscription<DevicePairingState>? _stateSub;
  bool _submitting = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // The BLoC stream is broadcast with no replay: subscribe in initState
    // (before any user action) so authorizeCode results are observed here.
    _stateSub = widget.pairingBloc.state.listen((state) {
      if (!mounted) {
        return;
      }
      if (state.phase == DevicePairingPhase.paired) {
        Navigator.of(context).pop(true);
      } else if (state.phase == DevicePairingPhase.scanFailed) {
        setState(() {
          _failed = true;
          _submitting = false;
        });
      }
    });
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _submitting = true;
      _failed = false;
    });
    await widget.pairingBloc.authorizeCode(text);
  }

  @override
  Widget build(BuildContext context) {
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
                  const Expanded(
                    child: Text(
                      'PAIR THIS DEVICE',
                      style: TextStyle(
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
              const Text(
                'Enter the pairing code shown on your primary device.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Paste the pairing code…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: VaultTheme.vaultBlue,
                  ),
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: Text(_submitting ? 'Authorizing…' : 'Authorize'),
                ),
              ),
              if (_failed)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'That code could not be authorized. Check it and try again.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

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
