import 'dart:async';

import '../../cdn/data/in_memory_cdn_repository.dart';
import '../domain/cdn_delivery_bloc.dart';
import '../domain/cdn_delivery_state.dart';

/// Local implementation of [CdnDeliveryBloc] (Task 12.3).
///
/// Manages delivery metrics collection and CDN configuration state.
/// Uses monotonic sequence guards to prevent stale state updates.
class LocalCdnDeliveryBloc implements CdnDeliveryBloc {
  final InMemoryCdnRepository _repository;

  final _controller = StreamController<CdnDeliveryState>.broadcast();
  var _sequence = 0;
  var _current = const CdnDeliveryState();
  bool _closed = false;

  LocalCdnDeliveryBloc({required InMemoryCdnRepository repository})
      : _repository = repository;

  @override
  Stream<CdnDeliveryState> get state => _controller.stream;

  @override
  CdnDeliveryState get current => _current;

  @override
  void startMeasuring() {
    if (_closed) return;
    final seq = ++_sequence;
    _current = _current.copyWith(phase: CdnDeliveryPhase.measuring);
    _emit();
    unawaited(_loadMetrics(seq));
  }

  @override
  void recordCacheHit(int bytesServed) {
    if (_closed) return;
    unawaited(_repository.recordCacheHit(bytesServed));
    // Update local state optimistically
    final old = _current.metrics;
    _current = _current.copyWith(
      metrics: old.copyWith(
        bytesFromCache: old.bytesFromCache + bytesServed,
        totalRequests: old.totalRequests + 1,
        cacheHits: old.cacheHits + 1,
      ),
    );
    _emit();
  }

  @override
  void recordDownload({
    required int bytesDownloaded,
    required int ttfbMs,
    required int downloadTimeMs,
  }) {
    if (_closed) return;
    unawaited(_repository.recordDownload(
      bytesDownloaded: bytesDownloaded,
      ttfbMs: ttfbMs,
      downloadTimeMs: downloadTimeMs,
    ));
    // Update local state optimistically
    final old = _current.metrics;
    final totalBytes = old.bytesDownloaded + bytesDownloaded;
    final totalTime = old.totalDownloadTimeMs + downloadTimeMs;
    final avgSpeed = totalTime > 0 ? (totalBytes * 1000 ~/ totalTime) : 0;
    _current = _current.copyWith(
      metrics: old.copyWith(
        ttfbMs: ttfbMs,
        bytesDownloaded: totalBytes,
        totalRequests: old.totalRequests + 1,
        avgDownloadSpeedBps: avgSpeed,
        totalDownloadTimeMs: totalTime,
      ),
    );
    _emit();
  }

  @override
  void recordFailure() {
    if (_closed) return;
    unawaited(_repository.recordFailure());
    final old = _current.metrics;
    _current = _current.copyWith(
      metrics: old.copyWith(failedDownloads: old.failedDownloads + 1),
    );
    _emit();
  }

  @override
  Future<void> refresh() async {
    if (_closed) return;
    final seq = ++_sequence;
    await _loadMetrics(seq);
  }

  @override
  void close() {
    _closed = true;
    _controller.close();
  }

  Future<void> _loadMetrics(int seq) async {
    try {
      final metrics = await _repository.getMetrics();
      if (_closed || seq != _sequence) return;
      _current = _current.copyWith(
        phase: CdnDeliveryPhase.ready,
        metrics: metrics,
      );
      _emit();
    } catch (e) {
      if (_closed || seq != _sequence) return;
      _current = _current.copyWith(
        phase: CdnDeliveryPhase.error,
        errorMessage: 'Failed to load CDN metrics',
      );
      _emit();
    }
  }

  void _emit() {
    if (!_closed && !_controller.isClosed) {
      _controller.add(_current);
    }
  }
}
