import 'dart:async';

import 'package:flutter/material.dart';

import '../../security/domain/root_detection_service.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/device_handle.dart';
import '../domain/device_pairing_bloc.dart';
import '../domain/device_pairing_state.dart';
import '../domain/linked_devices_bloc.dart';
import '../domain/linked_devices_state.dart';
import 'pairing_qr_view.dart';
import 'vault_theme.dart';

/// Device management sheet (Task 6.5).
///
/// Two flows on one FLAG_SECURE sheet:
///  - **Linked devices**: the [LinkedDevicesBloc] list with a revoke action
///    per device (rendered via [formatDeviceHandle] — never raw UUIDs).
///  - **Pair a new device**: the [DevicePairingBloc] QR flow — the primary
///    shows its pairing QR; the new device can also switch to entering the
///    code manually.
///
/// SECURITY CHECKPOINT (Task 6.5):
///  - The whole sheet is wrapped in [SecureScreenWrapper] (FLAG_SECURE).
///  - Only BLoC streams are consumed — no registry/network from the tree.
///  - Devices render ONLY through [formatDeviceHandle]; the QR payload is
///    rendered ONLY as a [PairingQrView] matrix — never as text.
class DeviceManagementSheet extends StatefulWidget {
  final LinkedDevicesBloc linkedDevicesBloc;
  final DevicePairingBloc pairingBloc;
  final SecureFlagService? secureFlagService;
  final RootDetectionService? rootDetectionService;

  const DeviceManagementSheet({
    super.key,
    required this.linkedDevicesBloc,
    required this.pairingBloc,
    this.secureFlagService,
    this.rootDetectionService,
  });

  /// Opens the sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required LinkedDevicesBloc linkedDevicesBloc,
    required DevicePairingBloc pairingBloc,
    SecureFlagService? secureFlagService,
    RootDetectionService? rootDetectionService,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => DeviceManagementSheet(
        linkedDevicesBloc: linkedDevicesBloc,
        pairingBloc: pairingBloc,
        secureFlagService: secureFlagService,
        rootDetectionService: rootDetectionService,
      ),
    );
  }

  @override
  State<DeviceManagementSheet> createState() => _DeviceManagementSheetState();
}

class _DeviceManagementSheetState extends State<DeviceManagementSheet> {
  LinkedDevicesState? _devices;
  DevicePairingState? _pairing;
  StreamSubscription<LinkedDevicesState>? _devicesSub;
  StreamSubscription<DevicePairingState>? _pairingSub;
  bool _showQr = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.linkedDevicesBloc.refresh());
    unawaited(widget.pairingBloc.start());
    _devicesSub = widget.linkedDevicesBloc.state.listen((s) {
      if (mounted) {
        setState(() => _devices = s);
      }
    });
    _pairingSub = widget.pairingBloc.state.listen((s) {
      if (mounted) {
        setState(() => _pairing = s);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_devicesSub?.cancel());
    unawaited(_pairingSub?.cancel());
    super.dispose();
  }

  void _startPairing() {
    setState(() => _showQr = true);
    unawaited(widget.pairingBloc.generatePairingCode());
  }

  void _revoke(String deviceId) {
    unawaited(widget.linkedDevicesBloc.revoke(deviceId));
  }

  @override
  Widget build(BuildContext context) {
    return _secure(
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'DEVICES',
                        style: TextStyle(
                          color: VaultTheme.vaultBlue,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const Divider(height: 1),
                _buildDevices(),
                const SizedBox(height: 12),
                _showQr ? _buildQrPanel() : _buildPairCta(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDevices() {
    final devices = _devices?.devices ?? const [];
    if (devices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text(
          'No linked devices yet. Pair one to use this account on another device.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }
    return Column(
      children: [
        for (final device in devices)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              radius: 16,
              backgroundColor: VaultTheme.vaultBlue,
              child: Icon(Icons.devices_rounded, color: Colors.white, size: 18),
            ),
            title: Text(
              formatDeviceHandle(device.deviceId),
              style: const TextStyle(
                fontFamily: VaultTheme.monoFont,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text('Paired ${_formatDate(device.pairedAt)}'),
            trailing: device.revoked
                ? const Text('REVOKED',
                    style: TextStyle(
                        color: Colors.black45,
                        fontSize: 11,
                        fontWeight: FontWeight.w700))
                : TextButton(
                    onPressed: () => _revoke(device.deviceId),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red[700],
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Revoke'),
                  ),
          ),
      ],
    );
  }

  Widget _buildPairCta() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _startPairing,
        style: FilledButton.styleFrom(backgroundColor: VaultTheme.vaultBlue),
        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
        label: const Text('Pair a new device'),
      ),
    );
  }

  Widget _buildQrPanel() {
    final pairing = _pairing;
    if (pairing == null ||
        pairing.phase != DevicePairingPhase.qrReady ||
        pairing.qrMatrix == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: VaultTheme.vaultBlue),
        ),
      );
    }
    final matrix = pairing.qrMatrix!;
    return Column(
      children: [
        PairingQrView(matrix: matrix, caption: 'Scan with your new device'),
        const SizedBox(height: 10),
        const Text(
          'Expires in 5 minutes · one-time use',
          style: TextStyle(color: Colors.black45, fontSize: 11),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => unawaited(widget.pairingBloc.reset()),
          style: OutlinedButton.styleFrom(
            foregroundColor: VaultTheme.vaultBlue,
            side: const BorderSide(color: VaultTheme.vaultBlue),
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final yyyy = local.year;
    return '$dd/$mm/$yyyy';
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
