import 'dart:async';

import 'package:civic_commons/deployment/domain/build_config.dart';
import 'package:civic_commons/deployment/domain/health_monitor.dart';
import 'package:civic_commons/state/domain/deployment_bloc.dart';
import 'package:civic_commons/state/domain/deployment_state.dart';
import 'package:civic_commons/state/ui/deployment_monitor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deployment Monitor Screen Tests (Task 14.1–14.4).
void main() {
  group('DeploymentMonitorScreen', () {
    testWidgets('renders title in AppBar', (tester) async {
      final bloc = FakeDeploymentBloc();
      await tester.pumpWidget(MaterialApp(
        home: DeploymentMonitorScreen(bloc: bloc),
      ));

      expect(find.text('Deployment Monitor'), findsOneWidget);
      bloc.close();
    });

    testWidgets('shows refresh button', (tester) async {
      final bloc = FakeDeploymentBloc();
      await tester.pumpWidget(MaterialApp(
        home: DeploymentMonitorScreen(bloc: bloc),
      ));

      expect(find.byIcon(Icons.refresh), findsOneWidget);
      bloc.close();
    });

    testWidgets('shows pipeline button', (tester) async {
      final bloc = FakeDeploymentBloc();
      await tester.pumpWidget(MaterialApp(
        home: DeploymentMonitorScreen(bloc: bloc),
      ));

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      bloc.close();
    });

    testWidgets('shows verification button', (tester) async {
      final bloc = FakeDeploymentBloc();
      await tester.pumpWidget(MaterialApp(
        home: DeploymentMonitorScreen(bloc: bloc),
      ));

      expect(find.byIcon(Icons.verified), findsOneWidget);
      bloc.close();
    });

    testWidgets('shows empty state when no data', (tester) async {
      final bloc = FakeDeploymentBloc();
      await tester.pumpWidget(MaterialApp(
        home: DeploymentMonitorScreen(bloc: bloc),
      ));

      expect(find.text('No deployment data yet.'), findsOneWidget);
      bloc.close();
    });

    testWidgets('shows build config when initialized', (tester) async {
      final bloc = FakeDeploymentBloc();
      bloc.emitState(const DeploymentState(
        buildConfig: EnvironmentConfig.production(),
      ));

      await tester.pumpWidget(MaterialApp(
        home: DeploymentMonitorScreen(bloc: bloc),
      ));

      expect(find.text('Build Configuration'), findsOneWidget);
      expect(find.text('Production'), findsWidgets);
      bloc.close();
    });

    testWidgets('shows health report when available', (tester) async {
      final bloc = FakeDeploymentBloc();
      bloc.emitState(DeploymentState(
        healthReport: HealthReport.empty(),
      ));

      await tester.pumpWidget(MaterialApp(
        home: DeploymentMonitorScreen(bloc: bloc),
      ));

      expect(find.text('Health Report'), findsOneWidget);
      bloc.close();
    });
  });
}

/// Fake DeploymentBloc for widget testing.
class FakeDeploymentBloc implements DeploymentBloc {
  DeploymentState _state = const DeploymentState();
  final _controller = StreamController<DeploymentState>.broadcast();

  @override
  Stream<DeploymentState> get stream => _controller.stream;

  @override
  DeploymentState get state => _state;

  void emitState(DeploymentState newState) {
    _state = newState;
    _controller.add(newState);
  }

  @override
  void initialize(EnvironmentConfig config) {
    emitState(DeploymentState(buildConfig: config));
  }

  @override
  void runPipeline() {}

  @override
  void runVerification() {}

  @override
  void refreshHealth() {}

  @override
  void reset() {
    emitState(const DeploymentState());
  }

  @override
  void close() {
    _controller.close();
  }
}
