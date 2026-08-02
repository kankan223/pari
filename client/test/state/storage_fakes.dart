import 'dart:typed_data';

import 'package:civic_commons/state/domain/hive_box_key_provider.dart';

/// Scripted [HiveBoxKeyProvider] fake — returns a 32-byte key only for box
/// names explicitly registered as sensitive (Task 3.6 tests).
class FakeHiveBoxKeyProvider implements HiveBoxKeyProvider {
  final Map<String, Uint8List> keys = {};

  /// Registers a deterministic 32-byte key for [boxName].
  void register(String boxName, {int fill = 7}) {
    keys[boxName] = Uint8List.fromList(List.filled(32, fill));
  }

  @override
  Future<Uint8List?> keyFor(String boxName) async => keys[boxName];
}
