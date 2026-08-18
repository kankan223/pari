import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/transparency_record.dart';

/// Real SHA-256 hasher for the transparency log (Task 10.5).
///
/// Uses the `cryptography` package (already a project dependency via
/// the karma engine, Task 10.2). Production-grade, deterministic.
class RealTransparencyHasher implements TransparencyHasher {
  const RealTransparencyHasher();

  @override
  Future<Uint8List> hash(List<int> bytes) async {
    return Uint8List.fromList((await Sha256().hash(bytes)).bytes);
  }
}
