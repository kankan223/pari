import 'package:civic_commons/consent/domain/consent_record.dart';
import 'package:civic_commons/consent/domain/consent_repository.dart';
import 'package:civic_commons/consent/domain/consent_type.dart';

/// In-memory implementation of [ConsentRepository] (Task 11.1).
///
/// Used in the testing harness and unit tests. Production persistence
/// backs onto the SQLCipher-encrypted database (deferred to Phase 9
/// integration).
///
/// SECURITY CHECKPOINT (11.1): stores only [ConsentRecord] objects
/// carrying consent types and timestamps — no identity, no PII, no tokens.
class InMemoryConsentRepository implements ConsentRepository {
  final Map<ConsentType, ConsentRecord> _consents = {};
  bool _dataDeleted = false;

  /// Callback invoked when [deleteUserData] is called.
  final VoidCallback? onDataDeleted;

  InMemoryConsentRepository({this.onDataDeleted});

  @override
  String get currentConsentVersion => '1.0';

  @override
  Future<ConsentRecord?> getConsent(ConsentType type) async => _consents[type];

  @override
  Future<List<ConsentRecord>> getAllConsents() async {
    return List<ConsentRecord>.unmodifiable(
      _consents.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
    );
  }

  @override
  Future<bool> hasConsent(ConsentType type) async {
    final record = _consents[type];
    return record != null && record.granted;
  }

  @override
  Future<void> grantConsent({
    required ConsentType type,
    required String consentVersion,
    required String textHash,
  }) async {
    _consents[type] = ConsentRecord(
      recordId: 'consent-${type.wireName}-$consentVersion',
      type: type,
      consentVersion: consentVersion,
      granted: true,
      timestamp: DateTime.now().toUtc(),
      textHash: textHash,
    );
  }

  @override
  Future<void> withdrawConsent(ConsentType type) async {
    final existing = _consents[type];
    if (existing != null && existing.granted) {
      _consents[type] = ConsentRecord(
        recordId:
            'withdrawal-${type.wireName}-${DateTime.now().millisecondsSinceEpoch}',
        type: type,
        consentVersion: existing.consentVersion,
        granted: false,
        timestamp: DateTime.now().toUtc(),
        textHash: existing.textHash,
      );
    }
  }

  @override
  Future<bool> hasAllRequiredConsents() async {
    for (final type in ConsentType.values) {
      if (type == ConsentType.analytics) continue; // optional
      if (!await hasConsent(type)) return false;
    }
    return true;
  }

  @override
  Future<void> deleteUserData() async {
    _dataDeleted = true;
    _consents.clear();
    onDataDeleted?.call();
  }

  /// Returns whether [deleteUserData] was called.
  bool get wasDataDeleted => _dataDeleted;
}

/// Void callback type.
typedef VoidCallback = void Function();
