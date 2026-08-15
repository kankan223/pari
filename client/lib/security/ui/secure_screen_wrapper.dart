import 'dart:async';

import 'package:flutter/material.dart';

import '../data/method_channel_secure_flag_service.dart';
import '../domain/root_detection_service.dart';
import '../domain/secure_flag_service.dart';
import '../domain/security_policy.dart';
import 'security_warning_banner.dart';

/// Wraps a protected screen (Vault, War Room) and enforces the platform
/// FLAG_SECURE guard so the content cannot be screenshotted, screen-recorded,
/// or previewed in the Android recents list.
///
/// Responsibilities:
/// 1. Enables FLAG_SECURE when the protected screen mounts.
/// 2. Disables FLAG_SECURE when the protected screen unmounts.
/// 3. Optionally runs the local root/jailbreak check and, if a warning
///    decision is produced, renders a [SecurityWarningBanner] above the
///    child — the user is NEVER blocked.
///
/// Clean Architecture: domain ports ([SecureFlagService],
/// [RootDetectionService]) are injected; production wiring uses the data-layer
/// implementations while tests inject fakes. All services default to the
/// real data-layer implementations.
///
/// Security contract:
/// - FLAG_SECURE and the integrity check are strictly local operations.
/// - The wrapper never blocks the user and never transmits any data.
class SecureScreenWrapper extends StatefulWidget {
  /// The protected screen content.
  final Widget child;

  /// FLAG_SECURE service (defaults to the MethodChannel implementation).
  final SecureFlagService secureFlagService;

  /// Local root detection (optional — when null, no warning is shown).
  final RootDetectionService? rootDetectionService;

  /// Policy mapping integrity → decision (warning, never block).
  final DeviceSecurityPolicy policy;

  const SecureScreenWrapper({
    super.key,
    required this.child,
    this.secureFlagService = const _DefaultSecureFlagService(),
    this.rootDetectionService,
    this.policy = const DeviceSecurityPolicy(),
  });

  @override
  State<SecureScreenWrapper> createState() => _SecureScreenWrapperState();
}

class _SecureScreenWrapperState extends State<SecureScreenWrapper> {
  SecurityDecision? _decision;

  @override
  void initState() {
    super.initState();
    unawaited(_activate());
  }

  @override
  void dispose() {
    // Best-effort cleanup: a failure here must never crash the app.
    unawaited(_safeDisableSecureFlag());
    super.dispose();
  }

  Future<void> _activate() async {
    // FLAG_SECURE failure must not prevent detection/warning: a rooted
    // device with a broken channel should still be warned. Graceful
    // degradation on every path — no channel failure may crash the screen.
    try {
      await widget.secureFlagService.enableSecureFlag();
    } catch (_) {
      // Unsupported/broken channel — the screen still renders (unguarded).
    }

    final detector = widget.rootDetectionService;
    if (detector == null) {
      return;
    }
    try {
      final integrity = await detector.detect();
      if (!mounted) {
        return;
      }
      setState(() => _decision = widget.policy.evaluate(integrity));
    } catch (_) {
      // A detection failure must never crash the protected screen.
    }
  }

  Future<void> _safeDisableSecureFlag() async {
    try {
      await widget.secureFlagService.disableSecureFlag();
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final decision = _decision;
    final showWarning =
        decision != null && decision.severity == SecuritySeverity.warning;
    return Column(
      children: [
        if (showWarning) const SecurityWarningBanner(),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// Const-constructible wrapper around the real channel service so the widget
/// can default to production wiring without a const violation.
class _DefaultSecureFlagService implements SecureFlagService {
  static final SecureFlagService _instance = MethodChannelSecureFlagService();

  const _DefaultSecureFlagService();

  @override
  Future<void> disableSecureFlag() => _instance.disableSecureFlag();

  @override
  Future<void> enableSecureFlag() => _instance.enableSecureFlag();

  @override
  Future<bool> isSecureFlagSupported() => _instance.isSecureFlagSupported();
}
