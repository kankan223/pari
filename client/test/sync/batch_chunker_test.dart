import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/sync/domain/batch_chunker.dart';

/// VERIFY (Task 3.4): chunking logic for batch operations (max 10 per batch).
void main() {
  group('BatchChunker - chunking logic', () {
    test('empty input yields no batches', () {
      expect(BatchChunker.chunk<int>([]), isEmpty);
    });

    test('fewer than max items is a single batch', () {
      final batches = BatchChunker.chunk([1, 2, 3]);
      expect(batches, hasLength(1));
      expect(batches.first, [1, 2, 3]);
    });

    test('exactly max items is a single batch of 10', () {
      final items = List.generate(10, (i) => i);
      final batches = BatchChunker.chunk(items);
      expect(batches, hasLength(1));
      expect(batches.first, hasLength(10));
    });

    test('11 items split into 10 + 1', () {
      final items = List.generate(11, (i) => i);
      final batches = BatchChunker.chunk(items);
      expect(batches, hasLength(2));
      expect(batches[0], hasLength(10));
      expect(batches[1], hasLength(1));
    });

    test('25 items split into 10 + 10 + 5', () {
      final items = List.generate(25, (i) => i);
      final batches = BatchChunker.chunk(items);
      expect(batches, hasLength(3));
      expect(batches[0], hasLength(10));
      expect(batches[1], hasLength(10));
      expect(batches[2], hasLength(5));
    });

    test('order is preserved across batches', () {
      final items = List.generate(23, (i) => i);
      final batches = BatchChunker.chunk(items);
      final flattened = batches.expand((b) => b).toList();
      expect(flattened, items);
    });

    test('no batch ever exceeds maxBatchSize', () {
      final items = List.generate(37, (i) => i);
      for (final batch in BatchChunker.chunk(items)) {
        expect(batch.length, lessThanOrEqualTo(10));
      }
    });

    test('custom maxBatchSize is respected', () {
      final items = List.generate(7, (i) => i);
      final batches = BatchChunker.chunk(items, maxBatchSize: 3);
      expect(batches, hasLength(3));
      expect(batches[0], hasLength(3));
      expect(batches[1], hasLength(3));
      expect(batches[2], hasLength(1));
    });

    test('non-positive maxBatchSize throws', () {
      expect(
        () => BatchChunker.chunk([1], maxBatchSize: 0),
        throwsArgumentError,
      );
    });
  });
}
