import 'package:civic_commons/scaling/data/in_memory_scaling_repository.dart';
import 'package:civic_commons/state/data/local_scaling_bloc.dart';
import 'package:civic_commons/state/ui/scaling_monitor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScalingMonitorScreen - Task 12.4', () {
    late LocalScalingBloc bloc;

    setUp(() {
      bloc = LocalScalingBloc(
        repository: InMemoryScalingRepository(),
      );
    });

    tearDown(() {
      bloc.close();
    });

    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScalingMonitorScreen(bloc: bloc),
      ));
      expect(find.text('SCALING MONITOR'), findsOneWidget);
    });

    testWidgets('has an AppBar with refresh button', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScalingMonitorScreen(bloc: bloc),
      ));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('has a ListView body', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScalingMonitorScreen(bloc: bloc),
      ));
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScalingMonitorScreen(bloc: bloc),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('refresh button triggers refresh without error',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScalingMonitorScreen(bloc: bloc),
      ));
      await tester.tap(find.byIcon(Icons.refresh));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('SCALING MONITOR'), findsOneWidget);
    });
  });
}
