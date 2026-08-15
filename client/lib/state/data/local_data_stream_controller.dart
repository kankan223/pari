import 'dart:async';

import '../domain/local_data_stream.dart';

/// Scriptable [LocalDataStream] (data layer) — a broadcast controller that
/// production code (or the repository layer) pushes database snapshots into,
/// and tests drive directly.
class LocalDataStreamController<T> implements LocalDataStream<T> {
  final StreamController<List<T>> _controller =
      StreamController<List<T>>.broadcast();

  @override
  Stream<List<T>> get changes => _controller.stream;

  /// Pushes a new snapshot to BLoC subscribers.
  void emit(List<T> snapshot) => _controller.add(snapshot);

  /// Closes the underlying stream.
  Future<void> close() => _controller.close();
}
