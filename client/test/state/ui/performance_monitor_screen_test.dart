import 'package:civic_commons/performance/data/in_memory_performance_repository.dart';
import 'package:civic_commons/performance/data/in_memory_startup_optimizer.dart';
import 'package:civic_commons/state/data/local_performance_bloc.dart';
import 'package:civic_commons/state/ui/performance_monitor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PerformanceMonitorScreen - Task 12.1', () {
    late LocalPerformanceBloc bloc;

    setUp(() {
      bloc = LocalPerformanceBloc(
        repository: InMemoryPerformanceRepository(),
        optimizer: InMemoryStartupOptimizer(),
      );
    });

    tearDown(() {
      bloc.close();
    });

    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PerformanceMonitorScreen(bloc: bloc),
      ));
      expect(find.text('PERFORMANCE MONITOR'), findsOneWidget);
    });

    testWidgets('has an AppBar with refresh button', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PerformanceMonitorScreen(bloc: bloc),
      ));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('has a ListView body', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PerformanceMonitorScreen(bloc: bloc),
      ));
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PerformanceMonitorScreen(bloc: bloc),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('refresh button triggers refresh without error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PerformanceMonitorScreen(bloc: bloc),
      ));
      await tester.tap(find.byIcon(Icons.refresh));
      // Multiple pumps to let async complete
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('PERFORMANCE MONITOR'), findsOneWidget);
    });
  });
}
