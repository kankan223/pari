/// Chunks a list into batches of at most [maxBatchSize] items (Task 3.4).
///
/// Pure domain logic — no async, no dependencies. Used by the background
/// sync worker so network operations are performed in small, bounded batches
/// (the master plan mandates a maximum of 10 items per batch).
class BatchChunker {
  /// Default maximum batch size per the master plan.
  static const int defaultMaxBatchSize = 10;

  const BatchChunker._();

  /// Splits [items] into consecutive batches of at most [maxBatchSize].
  ///
  /// Order is preserved; an empty input yields no batches; a batch never
  /// exceeds [maxBatchSize] elements.
  static List<List<T>> chunk<T>(
    List<T> items, {
    int maxBatchSize = defaultMaxBatchSize,
  }) {
    if (maxBatchSize <= 0) {
      throw ArgumentError.value(
        maxBatchSize,
        'maxBatchSize',
        'must be positive',
      );
    }
    final batches = <List<T>>[];
    for (var i = 0; i < items.length; i += maxBatchSize) {
      final end =
          (i + maxBatchSize < items.length) ? i + maxBatchSize : items.length;
      batches.add(items.sublist(i, end));
    }
    return batches;
  }
}
