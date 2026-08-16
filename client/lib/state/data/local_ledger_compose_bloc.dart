import 'dart:async';

import '../../ledger/domain/ledger_category.dart';
import '../../ledger/domain/ledger_draft_sink.dart';
import '../domain/ledger_compose_bloc.dart';
import '../domain/ledger_compose_state.dart';

/// Draft-collecting [LedgerComposeBloc] (data layer, Task 7.1).
///
/// Validates the draft against FR-L1 (exactly one pin code + one category,
/// non-empty headline, well-formed 6-digit pin) and persists it through the
/// injected [LedgerDraftSink]. Failures map to a generic [hasError] — no
/// reason-specific detail surfaces to the UI.
class LocalLedgerComposeBloc implements LedgerComposeBloc {
  final LedgerDraftSink _drafts;

  final StreamController<LedgerComposeState> _controller =
      StreamController<LedgerComposeState>.broadcast();

  /// The latest state (setters build on it so partial updates compose).
  LedgerComposeState _current = const LedgerComposeState();

  LocalLedgerComposeBloc({required LedgerDraftSink drafts}) : _drafts = drafts;

  @override
  Stream<LedgerComposeState> get state => _controller.stream;

  /// The latest emitted state (non-stream read for submit confirmation).
  @override
  LedgerComposeState get current => _current;

  @override
  Future<void> start() async {
    _current = const LedgerComposeState();
    _controller.add(_current);
  }

  @override
  Future<void> setCategory(LedgerCategory? category) async {
    _current = _current.copyWith(
      category: category,
      clearCategory: category == null,
    );
    _controller.add(_current);
  }

  @override
  Future<void> setPinCode(String pinCode) async {
    _current = _current.copyWith(pinCode: pinCode);
    _controller.add(_current);
  }

  @override
  Future<void> setHeadline(String headline) async {
    _current = _current.copyWith(headline: headline);
    _controller.add(_current);
  }

  @override
  Future<void> setBody(String body) async {
    _current = _current.copyWith(body: body);
    _controller.add(_current);
  }

  @override
  Future<void> submit() async {
    if (!_isValid(_current)) {
      _current = _current.copyWith(hasError: true);
      _controller.add(_current);
      return;
    }
    _current = _current.copyWith(status: LedgerComposeStatus.submitting);
    _controller.add(_current);
    try {
      await _drafts.save(
        LedgerDraft(
          category: _current.category!,
          pinCode: _current.pinCode,
          headline: _current.headline,
          body: _current.body,
        ),
      );
    } catch (_) {
      // A persistence failure must never crash the compose UI and must
      // never leak detail — the same generic error as a validation failure.
      _current = _current.copyWith(
        status: LedgerComposeStatus.error,
        hasError: true,
      );
      _controller.add(_current);
      return;
    }
    _current = _current.copyWith(status: LedgerComposeStatus.submitted);
    _controller.add(_current);
  }

  @override
  Future<void> reset() async {
    _current = const LedgerComposeState();
    _controller.add(_current);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  bool _isValid(LedgerComposeState s) =>
      s.category != null &&
      RegExp(r'^\d{6}$').hasMatch(s.pinCode) &&
      s.headline.trim().isNotEmpty;
}
