import 'package:civic_commons/state/data/local_audit_log_bloc.dart';
import 'package:civic_commons/state/data/local_cdn_delivery_bloc.dart';
import 'package:civic_commons/state/data/local_consent_bloc.dart';
import 'package:civic_commons/state/data/local_performance_bloc.dart';
import 'package:civic_commons/state/data/local_rate_limit_bloc.dart';
import 'package:civic_commons/state/data/local_scaling_bloc.dart';
import 'package:civic_commons/state/data/local_security_scan_bloc.dart';
import 'package:civic_commons/audit/data/in_memory_audit_repository.dart';
import 'package:civic_commons/cdn/data/in_memory_cdn_repository.dart';
import 'package:civic_commons/consent/data/in_memory_consent_repository.dart';
import 'package:civic_commons/performance/data/in_memory_performance_repository.dart';
import 'package:civic_commons/rate_limit/data/in_memory_rate_limit_repository.dart';
import 'package:civic_commons/rate_limit/domain/rate_limit_policy.dart';
import 'package:civic_commons/scaling/data/in_memory_scaling_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../security/fake_security_scanner.dart';

/// BLoC State Throughput Benchmarks (Task 13.5).
///
/// Measures event processing throughput and state stream emission latency
/// under rapid event bursts across core BLoCs. All benchmarks use in-memory
/// implementations with deterministic timing.
void main() {
  group('BLoC Throughput - LocalPerformanceBloc', () {
    late LocalPerformanceBloc bloc;

    setUp(() {
      bloc = LocalPerformanceBloc(
        repository: InMemoryPerformanceRepository(),
      );
    });

    tearDown(() => bloc.close());

    test('startMeasuring emits within acceptable time', () {
      final stopwatch = Stopwatch()..start();
      bloc.startMeasuring();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'startMeasuring should emit <100ms');
    });

    test('multiple rapid events do not crash', () {
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        bloc.recordColdStart(100 + i);
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(200),
          reason: '100 rapid events should process in <200ms');
    });

    test('refresh completes quickly', () {
      bloc.startMeasuring();

      final stopwatch = Stopwatch()..start();
      bloc.refresh();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'refresh should complete in <100ms');
    });
  });

  group('BLoC Throughput - LocalScalingBloc', () {
    late LocalScalingBloc bloc;

    setUp(() {
      bloc = LocalScalingBloc(
        repository: InMemoryScalingRepository(),
      );
    });

    tearDown(() => bloc.close());

    test('startMeasuring emits state', () {
      bloc.startMeasuring();

      expect(bloc.current, isNotNull);
    });

    test('recordRequest processes quickly', () {
      bloc.startMeasuring();

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 50; i++) {
        bloc.recordRequest(
          success: true,
          latencyMs: 50,
          shardId: 'default',
        );
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: '50 recordRequest calls should take <100ms');
    });
  });

  group('BLoC Throughput - LocalCdnDeliveryBloc', () {
    late LocalCdnDeliveryBloc bloc;

    setUp(() {
      bloc = LocalCdnDeliveryBloc(
        repository: InMemoryCdnRepository(),
      );
    });

    tearDown(() => bloc.close());

    test('startMeasuring emits state', () {
      bloc.startMeasuring();

      expect(bloc.state, isNotNull);
    });

    test('multiple metric updates are fast', () {
      bloc.startMeasuring();

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 50; i++) {
        bloc.recordCacheHit(1024);
        bloc.recordDownload(
          bytesDownloaded: 1024,
          ttfbMs: 50,
          downloadTimeMs: 100,
        );
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: '50 metric updates should take <100ms');
    });
  });

  group('BLoC Throughput - LocalConsentBloc', () {
    late LocalConsentBloc bloc;

    setUp(() {
      bloc = LocalConsentBloc(
        repository: InMemoryConsentRepository(),
      );
    });

    tearDown(() => bloc.close());

    test('refresh is fast', () {
      final stopwatch = Stopwatch()..start();
      bloc.refresh();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'refresh should complete in <100ms');
    });

    test('grantAll processes quickly', () {
      bloc.refresh();

      final stopwatch = Stopwatch()..start();
      bloc.grantAll();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'grantAll should complete in <100ms');
    });
  });

  group('BLoC Throughput - LocalAuditLogBloc', () {
    late LocalAuditLogBloc bloc;

    setUp(() {
      bloc = LocalAuditLogBloc(
        repository: InMemoryAuditRepository(),
      );
    });

    tearDown(() => bloc.close());

    test('refresh is fast', () {
      final stopwatch = Stopwatch()..start();
      bloc.refresh();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'refresh should complete in <100ms');
    });
  });

  group('BLoC Throughput - LocalRateLimitBloc', () {
    late LocalRateLimitBloc bloc;

    setUp(() {
      bloc = LocalRateLimitBloc(
        repository: InMemoryRateLimitRepository(),
      );
    });

    tearDown(() => bloc.close());

    test('recordRequest with policy is fast', () {
      final stopwatch = Stopwatch()..start();
      bloc.recordRequest(RateLimitPolicy.postCreation);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'recordRequest should complete in <100ms');
    });

    test('multiple rapid recordRequests are fast', () {
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        bloc.recordRequest(RateLimitPolicy.postCreation);
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(200),
          reason: '100 rapid recordRequests should take <200ms');
    });
  });

  group('BLoC Throughput - LocalSecurityScanBloc', () {
    late LocalSecurityScanBloc bloc;
    late FakeSecurityScanner scanner;

    setUp(() {
      scanner = FakeSecurityScanner();
      bloc = LocalSecurityScanBloc(scanner: scanner);
    });

    tearDown(() => bloc.close());

    test('startScan completes', () {
      final stopwatch = Stopwatch()..start();
      bloc.startScan();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'startScan should complete in <100ms');
    });

    test('runPenetrationTests completes', () {
      final stopwatch = Stopwatch()..start();
      bloc.runPenetrationTests();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'runPenetrationTests should complete in <100ms');
    });
  });
}
