import '../../ledger/domain/ledger_category.dart';

/// Lifecycle of the compose flow (Task 7.1).
enum LedgerComposeStatus {
  /// Form not yet submitted.
  idle,

  /// The draft is being validated + persisted locally.
  submitting,

  /// The draft was persisted to the local queue (pending review/publish).
  submitted,

  /// The draft failed validation — the UI shows a generic message.
  error,
}

/// Immutable BLoC state for the Ledger compose flow (Task 7.1).
///
/// SECURITY CHECKPOINT (Task 7.1): the state carries only the draft's
/// public fields (category, pin code, headline, body) — no identity, no
/// PII, no raw user data. The draft itself is stored encrypted at rest via
/// the offline-first queue in the repository layer.
class LedgerComposeState {
  final LedgerComposeStatus status;

  /// The selected category (null until chosen — FR-L1 requires exactly one).
  final LedgerCategory? category;

  /// The 6-digit pin code the post is scoped to (FR-L1).
  final String pinCode;

  /// The headline (state the issue plainly, DESIGN.md §7.3).
  final String headline;

  /// The body / details.
  final String body;

  /// Generic validation failure flag (no reason-specific detail).
  final bool hasError;

  const LedgerComposeState({
    this.status = LedgerComposeStatus.idle,
    this.category,
    this.pinCode = '',
    this.headline = '',
    this.body = '',
    this.hasError = false,
  });

  bool get isSubmitted => status == LedgerComposeStatus.submitted;

  LedgerComposeState copyWith({
    LedgerComposeStatus? status,
    LedgerCategory? category,
    bool clearCategory = false,
    String? pinCode,
    String? headline,
    String? body,
    bool? hasError,
  }) =>
      LedgerComposeState(
        status: status ?? this.status,
        category: clearCategory ? null : (category ?? this.category),
        pinCode: pinCode ?? this.pinCode,
        headline: headline ?? this.headline,
        body: body ?? this.body,
        hasError: hasError ?? this.hasError,
      );
}
