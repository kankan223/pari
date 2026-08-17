import '../../academy/domain/offline_module_cache.dart';

/// Lifecycle of the offline-cache view (Task 9.4).
enum AcademyOfflinePhase {
  /// No load attempted yet.
  idle,

  /// Loading the local cache snapshot.
  loading,

  /// Cache snapshot is available and the UI can render.
  ready,

  /// The cache could not be loaded — generic error state.
  failure,
}

/// Immutable BLoC state for offline module caching (Task 9.4).
///
/// SECURITY CHECKPOINT (Task 9.4): the state carries ONLY module cache
/// entries (UUID module-id keys + status + sizes) and public totals —
/// no content, no identity. [errorMessage] is always the SAME generic
/// string (no side channel, no reason-specific detail).
class AcademyOfflineState {
  final AcademyOfflinePhase phase;

  /// Cache entries keyed by the module's validated UUID v4 id.
  final Map<String, ModuleCacheEntry> entries;

  /// Total bytes of downloaded (ready) content — the offline budget in use.
  final int totalCachedBytes;

  /// True when total cached bytes exceed the offline budget (persistent
  /// storage warning).
  final bool storageWarning;

  /// Generic failure message — constant, never content-specific.
  final String errorMessage;

  const AcademyOfflineState({
    this.phase = AcademyOfflinePhase.idle,
    this.entries = const {},
    this.totalCachedBytes = 0,
    this.storageWarning = false,
    this.errorMessage = '',
  });

  bool get isReady => phase == AcademyOfflinePhase.ready;

  ModuleCacheEntry? entryFor(String moduleId) => entries[moduleId];

  AcademyOfflineState copyWith({
    AcademyOfflinePhase? phase,
    Map<String, ModuleCacheEntry>? entries,
    int? totalCachedBytes,
    bool? storageWarning,
    String? errorMessage,
  }) =>
      AcademyOfflineState(
        phase: phase ?? this.phase,
        entries: entries ?? this.entries,
        totalCachedBytes: totalCachedBytes ?? this.totalCachedBytes,
        storageWarning: storageWarning ?? this.storageWarning,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}
