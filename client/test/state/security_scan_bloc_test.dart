import 'package:civic_commons/state/data/local_security_scan_bloc.dart';
import 'package:civic_commons/state/domain/security_scan_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../security/fake_security_scanner.dart';

void main() {
  late FakeSecurityScanner fakeScanner;
  late LocalSecurityScanBloc bloc;

  setUp(() {
    fakeScanner = FakeSecurityScanner();
    bloc = LocalSecurityScanBloc(scanner: fakeScanner);
  });

  tearDown(() {
    bloc.close();
  });

  group('LocalSecurityScanBloc', () {
    test('initial state is idle', () {
      expect(bloc.state.status, SecurityScanStatus.idle);
      expect(bloc.state.isScanning, isFalse);
      expect(bloc.state.lastScanResult, isNull);
    });

    test('startScan transitions to scanning then completed', () async {
      final states = <SecurityScanState>[];
      bloc.stream.listen(states.add);

      bloc.startScan();
      await Future.delayed(Duration.zero);

      expect(states.length, greaterThanOrEqualTo(1));
      expect(bloc.state.status, SecurityScanStatus.completed);
      expect(bloc.state.isScanning, isFalse);
      expect(bloc.state.lastScanResult, isNotNull);
    });

    test('startScan sets scanning state during scan', () async {
      fakeScanner.scanDelay = const Duration(milliseconds: 50);

      final states = <SecurityScanState>[];
      bloc.stream.listen(states.add);

      bloc.startScan();
      // Check immediately - should be scanning
      expect(bloc.state.isScanning, isTrue);
      expect(bloc.state.status, SecurityScanStatus.scanning);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(bloc.state.status, SecurityScanStatus.completed);
    });

    test('startScan handles scanner errors', () async {
      fakeScanner.shouldFailScan = true;

      bloc.startScan();
      await Future.delayed(Duration.zero);

      expect(bloc.state.status, SecurityScanStatus.error);
      expect(bloc.state.errorMessage, isNotNull);
      expect(bloc.state.isScanning, isFalse);
    });

    test('startScan is idempotent while scanning', () async {
      fakeScanner.scanDelay = const Duration(milliseconds: 50);

      bloc.startScan();
      bloc.startScan(); // Should be ignored

      await Future.delayed(const Duration(milliseconds: 100));
      expect(bloc.state.status, SecurityScanStatus.completed);
    });

    test('runPenetrationTests transitions to pentesting then completed',
        () async {
      final states = <SecurityScanState>[];
      bloc.stream.listen(states.add);

      bloc.runPenetrationTests();
      await Future.delayed(Duration.zero);

      expect(bloc.state.pentestResults, isNotEmpty);
      expect(bloc.state.isRunningPentests, isFalse);
      expect(bloc.state.status, SecurityScanStatus.completed);
    });

    test('runPenetrationTests handles errors', () async {
      fakeScanner.shouldFailPentests = true;

      bloc.runPenetrationTests();
      await Future.delayed(Duration.zero);

      expect(bloc.state.errorMessage, isNotNull);
      expect(bloc.state.isRunningPentests, isFalse);
    });

    test('refresh calls startScan', () async {
      bloc.refresh();
      await Future.delayed(Duration.zero);

      expect(bloc.state.status, SecurityScanStatus.completed);
      expect(bloc.state.lastScanResult, isNotNull);
    });

    test('acknowledgeFinding marks finding as acknowledged', () async {
      bloc.startScan();
      await Future.delayed(Duration.zero);

      final finding = bloc.state.lastScanResult!.findings.first;
      expect(finding.acknowledged, isFalse);

      bloc.acknowledgeFinding(finding.id);

      final updated = bloc.state.lastScanResult!.findings
          .firstWhere((f) => f.id == finding.id);
      expect(updated.acknowledged, isTrue);
    });

    test('acknowledgeFinding is no-op when no scan result', () {
      bloc.acknowledgeFinding('nonexistent-id');
      expect(bloc.state.lastScanResult, isNull);
    });
  });
}
