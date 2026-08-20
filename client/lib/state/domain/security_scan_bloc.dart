import 'security_scan_state.dart';

/// Port for the security scan BLoC (Task 13.4).
///
/// Provides a stream of [SecurityScanState] and actions to trigger scans,
/// acknowledge findings, and run penetration tests.
abstract class SecurityScanBloc {
  /// Current state stream.
  Stream<SecurityScanState> get stream;

  /// Current state value.
  SecurityScanState get state;

  /// Trigger a full codebase security scan.
  void startScan();

  /// Run all penetration test scenarios.
  void runPenetrationTests();

  /// Acknowledge a specific finding by ID.
  void acknowledgeFinding(String findingId);

  /// Refresh the current state.
  void refresh();

  /// Close the bloc and release resources.
  void close();
}
