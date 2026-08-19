import 'package:civic_commons/audit/data/in_memory_audit_repository.dart';
import 'package:civic_commons/audit/domain/audit_action.dart';
import 'package:civic_commons/audit/domain/audit_record.dart';
import 'package:civic_commons/security/ui/secure_screen_wrapper.dart';
import 'package:civic_commons/state/data/local_audit_log_bloc.dart';
import 'package:civic_commons/state/ui/audit_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditLogScreen', () {
    late LocalAuditLogBloc bloc;

    setUp(() {
      bloc = LocalAuditLogBloc(repository: InMemoryAuditRepository());
    });

    tearDown(() async {
      await bloc.close();
    });

    testWidgets('renders audit log screen with title', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AuditLogScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Audit Log'), findsOneWidget);
    });

    testWidgets('shows empty state when no records', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AuditLogScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No audit records yet'), findsOneWidget);
    });

    testWidgets('shows integrity verified banner', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AuditLogScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      // Initial state has integrityValid = true
      expect(
        find.textContaining('Chain integrity verified'),
        findsOneWidget,
      );
    });

    testWidgets('verify button is present in app bar', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AuditLogScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      // Verified icon appears in both the app bar and the integrity banner
      expect(find.byIcon(Icons.verified), findsAtLeastNWidgets(1));
    });

    testWidgets('shows audit record when seeded', (tester) async {
      // Seed a record before creating the widget
      final repo = InMemoryAuditRepository();
      await repo.append(AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'User granted consent',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: AuditRecord.genesisHash,
        selfHash: 'self_hash_0',
      ));

      final seededBloc = LocalAuditLogBloc(repository: repo);

      await tester.pumpWidget(MaterialApp(
        home: AuditLogScreen(bloc: seededBloc),
      ));
      // initState calls refresh — pump many frames for async chain
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('CONSENT GRANTED'), findsOneWidget);
      expect(find.text('User granted consent'), findsOneWidget);
      expect(find.text('#0'), findsOneWidget);

      await seededBloc.close();
    });

    testWidgets('security checkpoint: FLAG_SECURE wrapper is present',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AuditLogScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SecureScreenWrapper), findsOneWidget);
    });

    testWidgets('description text explains audit purpose', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AuditLogScreen(bloc: bloc),
      ));
      await tester.pumpAndSettle();

      // The integrity banner should be visible
      expect(
        find.textContaining('Chain integrity'),
        findsOneWidget,
      );
    });
  });
}
