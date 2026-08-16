import 'dart:math';

import '../domain/ledger_draft_sink.dart';

/// In-memory [LedgerDraftSink] (data layer, Task 7.1).
///
/// Local persistence seam for the compose flow — stores drafts in memory,
/// keyed by generated ids. The production implementation (SQLCipher +
/// offline queue) lands with the Phase 7 data work; this keeps the UI +
/// BLoC fully testable today.
class InMemoryLedgerDraftSink implements LedgerDraftSink {
  final Map<String, LedgerDraft> _drafts = {};
  final Random _random;

  InMemoryLedgerDraftSink({Random? random}) : _random = random ?? Random();

  List<LedgerDraft> get saved => _drafts.values.toList(growable: false);

  @override
  Future<String> save(LedgerDraft draft) async {
    final id = 'draft_${_random.nextInt(1 << 31)}';
    _drafts[id] = draft;
    return id;
  }
}
