import 'package:civic_commons/cdn/data/in_memory_cdn_repository.dart';
import 'package:civic_commons/state/data/local_cdn_delivery_bloc.dart';
import 'package:civic_commons/state/ui/cdn_delivery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CdnDeliveryScreen - Task 12.3', () {
    late LocalCdnDeliveryBloc bloc;

    setUp(() {
      bloc = LocalCdnDeliveryBloc(
        repository: InMemoryCdnRepository(),
      );
    });

    tearDown(() {
      bloc.close();
    });

    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CdnDeliveryScreen(bloc: bloc),
      ));
      expect(find.text('CDN DELIVERY'), findsOneWidget);
    });

    testWidgets('has an AppBar with refresh button', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CdnDeliveryScreen(bloc: bloc),
      ));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('has a ListView body', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CdnDeliveryScreen(bloc: bloc),
      ));
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CdnDeliveryScreen(bloc: bloc),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('refresh button triggers refresh without error',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CdnDeliveryScreen(bloc: bloc),
      ));
      await tester.tap(find.byIcon(Icons.refresh));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('CDN DELIVERY'), findsOneWidget);
    });
  });
}
