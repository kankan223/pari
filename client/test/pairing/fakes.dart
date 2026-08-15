import 'package:civic_commons/pairing/domain/device_registry.dart';
import 'package:civic_commons/pairing/domain/identity_key_source.dart';
import 'package:civic_commons/pairing/domain/linked_device.dart';
import 'package:civic_commons/pairing/domain/qr_matrix.dart';
import 'package:cryptography/cryptography.dart';

/// In-memory [QrEncoder] that records the encoded payload for assertions.
class FakeQrEncoder implements QrEncoder {
  final List<String> encoded = [];

  /// Deterministic 21×21 matrix (QR version 1 size) so tests can assert the
  /// matrix shape without the real encoder.
  @override
  QrMatrix encode(String data) {
    encoded.add(data);
    final rows = List<List<bool>>.generate(21, (_) => List.filled(21, false));
    // Corner finder pattern (dark 7×7 top-left) so the matrix is non-trivial.
    for (var i = 0; i < 7; i++) {
      for (var j = 0; j < 7; j++) {
        final ring = i == 0 || i == 6 || j == 0 || j == 6;
        final core = i >= 2 && i <= 4 && j >= 2 && j <= 4;
        rows[i][j] = ring || core;
      }
    }
    return QrMatrix.fromRows(rows);
  }
}

/// Scripted [QrScanner].
class FakeQrScanner implements QrScanner {
  /// The text the next [scan] returns (null simulates "no code found").
  String? nextScan;

  int scanCount = 0;

  @override
  Future<String?> scan() async {
    scanCount++;
    return nextScan;
  }
}

/// In-memory [DeviceRegistry].
class InMemoryDeviceRegistry implements DeviceRegistry {
  final Map<String, LinkedDevice> _devices = {};

  @override
  Future<void> add(LinkedDevice device) async {
    _devices[device.deviceId] = device;
  }

  @override
  Future<LinkedDevice?> getById(String deviceId) async => _devices[deviceId];

  @override
  Future<List<LinkedDevice>> list(String ownerBlindHash) async {
    final owned = _devices.values
        .where((d) => d.ownerBlindHash == ownerBlindHash)
        .toList();
    owned.sort((a, b) => b.pairedAt.compareTo(a.pairedAt));
    return owned;
  }

  @override
  Future<void> revoke(String deviceId) async {
    final device = _devices[deviceId];
    if (device == null || device.revoked) {
      return;
    }
    _devices[deviceId] = device.copyWith(revoked: true);
  }
}

/// In-memory [IdentityKeySource] backed by a fixed Ed25519 key pair.
class FakeIdentityKeySource implements IdentityKeySource {
  final SimpleKeyPair keyPair;
  final int loadCount;

  FakeIdentityKeySource(this.keyPair, {this.loadCount = 0});

  @override
  Future<SimpleKeyPair> loadOrCreateIdentityKeyPair() async => keyPair;

  @override
  Future<SimplePublicKey> loadIdentityPublicKey() async =>
      keyPair.extractPublicKey();
}
