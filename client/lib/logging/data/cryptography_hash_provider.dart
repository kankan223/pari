import 'dart:convert';

import 'package:convert/convert.dart' show hex;
import 'package:cryptography/cryptography.dart';

import '../domain/hash_provider.dart';

/// SHA-256 [HashProvider] implementation backed by the `cryptography` package
/// (data layer).
///
/// SHA-256 is a cryptographically secure one-way hash: preimage resistant and
/// collision resistant for practical purposes. Only the digest is ever logged.
class CryptographyHashProvider implements HashProvider {
  const CryptographyHashProvider();

  @override
  Future<String> sha256Hex(String input) async {
    final hash = await Sha256().hash(utf8.encode(input));
    return hex.encode(hash.bytes);
  }
}
