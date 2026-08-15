/// Sync status presented to the UI (Task 3.5; rendered by 5.4).
///
/// Mirrors the master plan's state machine:
/// - [live]: online, no pending work — the UI shows fresh local data.
/// - [cached]: online but serving from the local cache while a sync runs.
/// - [queued]: offline-first — mutations are queued awaiting connectivity.
/// - [offline]: no connectivity; the UI operates fully offline.
enum SyncStatus { live, cached, queued, offline }
