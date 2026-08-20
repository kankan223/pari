import 'dart:async';

import 'package:civic_commons/security/domain/security_scan_result.dart';
import 'package:civic_commons/security/domain/security_scanner_port.dart';

import '../domain/security_scan_bloc.dart';
import '../domain/security_scan_state.dart';

/// Local implementation of [SecurityScanBloc] (Task 13.4).
///
/// Coordinates the security scanner port and maintains scan state.
/// Uses monotonic sequence stale-drop pattern for stream safety.
///
/// Security contract:
/// - All scan results are kept local — never transmitted.
/// - Findings carry file paths only — zero PII.
class LocalSecurityScanBloc implements SecurityScanBloc {
  final SecurityScannerPort _scanner;

  final _controller = StreamController<SecurityScanState>.broadcast();
  var _state = const SecurityScanState();
  var _sequence = 0;

  LocalSecurityScanBloc({required SecurityScannerPort scanner})
      : _scanner = scanner;

  @override
  Stream<SecurityScanState> get stream => _controller.stream;

  @override
  SecurityScanState get state => _state;

  @override
  void startScan() async {
    if (_state.isScanning) return;

    _sequence++;
    final seq = _sequence;
    _state = _state.copyWith(
      status: SecurityScanStatus.scanning,
      isScanning: true,
      errorMessage: null,
    );
    _emit();

    try {
      final result = await _scanner.scanCodebase();

      // Stale-drop: ignore if a newer operation started
      if (seq != _sequence) return;

      _state = _state.copyWith(
        status: SecurityScanStatus.completed,
        lastScanResult: result,
        isScanning: false,
        errorMessage: null,
      );
    } catch (e) {
      if (seq != _sequence) return;
      _state = _state.copyWith(
        status: SecurityScanStatus.error,
        isScanning: false,
        errorMessage: 'Scan failed: $e',
      );
    }
    _emit();
  }

  @override
  void runPenetrationTests() async {
    if (_state.isRunningPentests) return;

    _sequence++;
    final seq = _sequence;
    _state = _state.copyWith(
      isRunningPentests: true,
      errorMessage: null,
    );
    _emit();

    try {
      final results = await _scanner.runAllPenetrationTests();

      if (seq != _sequence) return;

      _state = _state.copyWith(
        pentestResults: results,
        isRunningPentests: false,
        status: SecurityScanStatus.completed,
      );
    } catch (e) {
      if (seq != _sequence) return;
      _state = _state.copyWith(
        isRunningPentests: false,
        errorMessage: 'Penetration tests failed: $e',
      );
    }
    _emit();
  }

  @override
  void acknowledgeFinding(String findingId) {
    final result = _state.lastScanResult;
    if (result == null) return;

    final updatedFindings =
        result.findings.map((f) {
          if (f.id == findingId) return f.copyWith(acknowledged: true);
          return f;
        }).toList();

    final acknowledged = result.findings
        .where((f) => f.id == findingId)
        .toList();      _state = _state.copyWith(
        lastScanResult: SecurityScanResult(
          scanId: result.scanId,
          startedAtMs: result.startedAtMs,
          completedAtMs: result.completedAtMs,
          findings: updatedFindings,
          filesScanned: result.filesScanned,
          linesAnalyzed: result.linesAnalyzed,
        ),
      acknowledgedFindings: [
        ..._state.acknowledgedFindings,
        ...acknowledged,
      ],
    );
    _emit();
  }

  @override
  void refresh() {
    startScan();
  }

  @override
  void close() {
    _controller.close();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_state);
    }
  }
}
