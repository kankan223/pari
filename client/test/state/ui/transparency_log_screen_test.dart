import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_transparency_log_bloc.dart';
import 'package:civic_commons/state/ui/transparency_log_screen.dart';
import 'package:civic_commons/transparency/data/in_memory_transparency_repository.dart';
import 'package:civic_commons/transparency/domain/transparency_action.dart';
import 'package:civic_commons/transparency/domain/transparency_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTransparencyRepository repo;
  late LocalTransparencyLogBloc bloc;

  setUp(() {
    repo = InMemoryTransparencyRepository();
    bloc = LocalTransparencyLogBloc(
      repository: repo,
      pinCode: '800001',
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  Widget buildScreen() => MaterialApp(
        home: TransparencyLogScreen(
          bloc: bloc,
          secureFlagService: _FakeSecureFlagService(),
        ),
      );

  testWidgets('renders transparency log title', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Transparency Log'), findsOneWidget);
  });

  testWidgets('shows empty state when no records', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('No transparency records'), findsOneWidget);
  });

  testWidgets('shows integrity verified when chain is valid', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Chain integrity verified'), findsOneWidget);
  });

  testWidgets('renders records when seeded', (tester) async {
    await repo.append(TransparencyRecord(
      seq: 0,
      recordId: 'rec-001',
      action: TransparencyAction.moderationAction,
      summary: 'Post flagged for review',
      pinCode: '800001',
      occurredAt: DateTime.utc(2026, 8, 18, 10),
      prevHash: TransparencyRecord.genesisHash,
      selfHash: 'fake_hash',
    ));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Post flagged for review'), findsOneWidget);
    expect(find.text('1 record'), findsOneWidget);
  });

  testWidgets('verify integrity button is present', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.verified_user), findsOneWidget);
  });
}

class _FakeSecureFlagService implements SecureFlagService {
  @override
  Future<void> enableSecureFlag() async {}

  @override
  Future<void> disableSecureFlag() async {}

  @override
  Future<bool> isSecureFlagSupported() async => false;
}
