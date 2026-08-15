import '../../repository/domain/connection_request.dart';
import 'pending_request_summary.dart';

/// Immutable BLoC state for the Vault pending-requests inbox (Task 6.2).
///
/// [pending] lists the requests targeting the CURRENT user that are still
/// awaiting approval. Each is a UI-safe [PendingRequestSummary] — the raw
/// request id and the requester's blind hash are never exposed to widgets
/// beyond the summary projection.
class ConnectionRequestsState {
  final List<PendingRequestSummary> pending;
  final bool hasLoaded;

  const ConnectionRequestsState({
    this.pending = const [],
    this.hasLoaded = false,
  });

  ConnectionRequestsState copyWith({
    List<PendingRequestSummary>? pending,
    bool? hasLoaded,
  }) =>
      ConnectionRequestsState(
        pending: pending ?? this.pending,
        hasLoaded: hasLoaded ?? this.hasLoaded,
      );

  /// Pending requests from [requests] (the local connection_requests
  /// snapshot) that target [myBlindHash] and are still pending.
  static List<ConnectionRequest> incomingPending(
    List<ConnectionRequest> requests,
    String myBlindHash,
  ) =>
      requests
          .where((r) =>
              r.recipientHash == myBlindHash &&
              r.status == ConnectionRequestStatus.pending)
          .toList(growable: false);
}
