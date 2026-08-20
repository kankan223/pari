import 'dart:async';

import 'package:civic_commons/state/domain/security_scan_bloc.dart';
import 'package:civic_commons/state/domain/security_scan_state.dart';
import 'package:civic_commons/state/ui/security_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecurityScanScreen', () {
    testWidgets('renders title in AppBar', (tester) async {
      final bloc = FakeSecurityScanBloc();
      await tester.pumpWidget(MaterialApp(
        home: SecurityScanScreen(bloc: bloc),
      ));

      expect(find.text('Security Scanner'), findsOneWidget);
      bloc.close();
    });

    testWidgets('shows play button for scan', (tester) async {
      final bloc = FakeSecurityScanBloc();
      await tester.pumpWidget(MaterialApp(
        home: SecurityScanScreen(bloc: bloc),
      ));

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      bloc.close();
    });

    testWidgets('shows security button for penetration tests', (tester) async {
      final bloc = FakeSecurityScanBloc();
      await tester.pumpWidget(MaterialApp(
        home: SecurityScanScreen(bloc: bloc),
      ));

      // Security icon appears in AppBar and empty state
      expect(find.byIcon(Icons.security), findsAtLeastNWidgets(1));
      bloc.close();
    });

    testWidgets('shows empty state when no scans run', (tester) async {
      final bloc = FakeSecurityScanBloc();
      await tester.pumpWidget(MaterialApp(
        home: SecurityScanScreen(bloc: bloc),
      ));

      expect(find.text('No scans have been run yet.'), findsOneWidget);
      bloc.close();
    });

    testWidgets('shows scanning indicator when scanning', (tester) async {
      final bloc = FakeSecurityScanBloc();
      bloc.emitState(const SecurityScanState(
        status: SecurityScanStatus.scanning,
        isScanning: true,
      ));

      await tester.pumpWidget(MaterialApp(
        home: SecurityScanScreen(bloc: bloc),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('Scanning codebase for vulnerabilities...'),
        findsOneWidget,
      );
      bloc.close();
    });

    testWidgets('shows error state with retry button', (tester) async {
      final bloc = FakeSecurityScanBloc();
      bloc.emitState(const SecurityScanState(
        status: SecurityScanStatus.error,
        errorMessage: 'Scan failed',
      ));

      await tester.pumpWidget(MaterialApp(
        home: SecurityScanScreen(bloc: bloc),
      ));

      expect(find.text('Scan failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      bloc.close();
    });
  });
}

/// Fake SecurityScanBloc for widget testing.
class FakeSecurityScanBloc implements SecurityScanBloc {
  SecurityScanState _state = const SecurityScanState();
  final _controller = StreamController<SecurityScanState>.broadcast();

  @override
  Stream<SecurityScanState> get stream => _controller.stream;

  @override
  SecurityScanState get state => _state;

  void emitState(SecurityScanState newState) {
    _state = newState;
    _controller.add(newState);
  }

  @override
  void startScan() {
    emitState(const SecurityScanState(
      status: SecurityScanStatus.scanning,
      isScanning: true,
    ));
  }

  @override
  void runPenetrationTests() {
    emitState(const SecurityScanState(
      isRunningPentests: true,
    ));
  }

  @override
  void acknowledgeFinding(String findingId) {}

  @override
  void refresh() => startScan();

  @override
  void close() {
    _controller.close();
  }
}
