import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the local block list and report history.
///
/// SECURITY: stores only blind_hash_ids — never phone numbers, usernames,
/// or any PII. All data stays on device.
class BlockingService {
  final FlutterSecureStorage _storage;
  final _blockedController = StreamController<Set<String>>.broadcast();

  static const _blockedKey = 'blocked_users';
  static const _reportsKey = 'user_reports';

  BlockingService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Stream of currently blocked user hashes (broadcast).
  Stream<Set<String>> get blockedUsers => _blockedController.stream;

  /// Load the blocked set from secure storage.
  Future<Set<String>> loadBlocked() async {
    try {
      final json = await _storage.read(key: _blockedKey);
      if (json == null || json.isEmpty) return {};
      final list = (jsonDecode(json) as List).cast<String>();
      return Set<String>.from(list);
    } catch (_) {
      return {};
    }
  }

  /// Check if a user hash is blocked.
  Future<bool> isBlocked(String blindHashId) async {
    final blocked = await loadBlocked();
    return blocked.contains(blindHashId);
  }

  /// Block a user. Returns true if newly blocked, false if already blocked.
  Future<bool> block(String blindHashId) async {
    final blocked = await loadBlocked();
    if (blocked.contains(blindHashId)) return false;
    blocked.add(blindHashId);
    await _saveBlocked(blocked);
    _blockedController.add(blocked);
    return true;
  }

  /// Unblock a user. Returns true if was blocked, false otherwise.
  Future<bool> unblock(String blindHashId) async {
    final blocked = await loadBlocked();
    if (!blocked.contains(blindHashId)) return false;
    blocked.remove(blindHashId);
    await _saveBlocked(blocked);
    _blockedController.add(blocked);
    return true;
  }

  Future<void> _saveBlocked(Set<String> blocked) async {
    await _storage.write(
      key: _blockedKey,
      value: jsonEncode(blocked.toList()),
    );
  }

  /// Report a user with a reason category.
  Future<void> report({
    required String blindHashId,
    required String reason,
    String? details,
  }) async {
    try {
      final json = await _storage.read(key: _reportsKey);
      final list = json != null
          ? (jsonDecode(json) as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      list.add({
        'blind_hash_id': blindHashId,
        'reason': reason,
        'details': details ?? '',
        'reported_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _storage.write(key: _reportsKey, value: jsonEncode(list));
    } catch (_) {
      // Report storage is best-effort.
    }
  }

  /// Get all reports filed by this user.
  Future<List<Map<String, dynamic>>> getReports() async {
    try {
      final json = await _storage.read(key: _reportsKey);
      if (json == null || json.isEmpty) return [];
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Clear all blocked users and reports (for testing).
  Future<void> clearAll() async {
    await Future.wait([
      _storage.delete(key: _blockedKey),
      _storage.delete(key: _reportsKey),
    ]);
    _blockedController.add({});
  }

  void dispose() {
    _blockedController.close();
  }
}

/// Reason categories for user reports.
enum ReportReason {
  spam('Spam or unwanted messages'),
  harassment('Harassment or bullying'),
  impersonation('Impersonation or fake identity'),
  threats('Threats or violence'),
  inappropriate('Inappropriate content'),
  other('Other');

  final String label;
  const ReportReason(this.label);
}
