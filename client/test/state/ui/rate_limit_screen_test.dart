import 'package:civic_commons/rate_limit/data/in_memory_rate_limit_repository.dart';
import 'package:civic_commons/security/ui/secure_screen_wrapper.dart';
import 'package:civic_commons/state/data/local_rate_limit_bloc.dart';
import 'package:civic_commons/state/ui/rate_limit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryRateLimitRepository repo;
  late LocalRateLimitBloc bloc;

  setUp(() {
    repo = InMemoryRateLimitRepository();
    bloc = LocalRateLimitBloc(repository: repo);
  });

  tearDown(() async {
    await bloc.close();
  });

  Widget buildScreen() {
    return MaterialApp(
      home: RateLimitScreen(bloc: bloc),
    );
  }

  testWidgets('renders title and first policy', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('RATE LIMITS'), findsOneWidget);
    expect(find.text('POLICY STATUS'), findsOneWidget);
    expect(find.text('OTP Request'), findsOneWidget);
  });

  testWidgets('shows second policy', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Login Attempt'), findsOneWidget);
  });

  testWidgets('shows refresh button', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('FLAG_SECURE wrapper is present', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byType(SecureScreenWrapper), findsOneWidget);
  });

  testWidgets('renders without errors when empty', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byType(RateLimitScreen), findsOneWidget);
  });
}
