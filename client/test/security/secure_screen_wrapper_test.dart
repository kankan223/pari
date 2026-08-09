import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/security/domain/root_detection_service.dart';
import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/security/ui/secure_screen_wrapper.dart';
import 'package:civic_commons/security/ui/security_warning_banner.dart';

/// In-memory fake FLAG_SECURE service recording all calls.
class FakeSecureFlagService implements SecureFlagService {
  bool supported;
  int enableCalls = 0;
  int disableCalls = 0;
  bool throwOnEnable = false;
  bool throwOnDisable = false;

  FakeSecureFlagService({this.supported = true});

  @override
  Future<void> disableSecureFlag() async {
    disableCalls++;
    if (throwOnDisable) {
      throw Exception('channel error');
    }
  }

  @override
  Future<void> enableSecureFlag() async {
    enableCalls++;
    if (throwOnEnable) {
      throw Exception('channel error');
    }
  }

  @override
  Future<bool> isSecureFlagSupported() async => supported;
}

/// Fake root detector returning a configurable integrity result.
class FakeRootDetectionService implements RootDetectionService {
  final DeviceIntegrity integrity;
  int detectCalls = 0;

  FakeRootDetectionService({required this.integrity});

  @override
  Future<DeviceIntegrity> detect() async {
    detectCalls++;
    return integrity;
  }
}

const _clean = DeviceIntegrity(
  isRooted: false,
  isJailbroken: false,
  triggeredChecks: [],
);

const _rooted = DeviceIntegrity(
  isRooted: true,
  isJailbroken: false,
  triggeredChecks: [RootCheck.suBinaryPresent],
);

void main() {
  group('SecureScreenWrapper - FLAG_SECURE lifecycle', () {
    testWidgets('enables FLAG_SECURE on mount', (tester) async {
      final flag = FakeSecureFlagService();

      await tester.pumpWidget(
        MaterialApp(
          home: SecureScreenWrapper(
            secureFlagService: flag,
            child: const Text('Vault'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(flag.enableCalls, 1);
      expect(flag.disableCalls, 0);
      expect(find.text('Vault'), findsOneWidget);
    });

    testWidgets('disables FLAG_SECURE on unmount', (tester) async {
      final flag = FakeSecureFlagService();

      await tester.pumpWidget(
        MaterialApp(
          home: SecureScreenWrapper(
            secureFlagService: flag,
            child: const Text('War Room'),
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(flag.enableCalls, 1);
      expect(flag.disableCalls, 1);
    });
  });

  group('SecureScreenWrapper - graceful degradation (warning, not block)', () {
    testWidgets('shows a warning banner for a rooted device but keeps content',
        (tester) async {
      final detector = FakeRootDetectionService(integrity: _rooted);

      await tester.pumpWidget(
        MaterialApp(
          home: SecureScreenWrapper(
            secureFlagService: FakeSecureFlagService(),
            rootDetectionService: detector,
            child: const Text('Vault Content'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(detector.detectCalls, 1);
      expect(find.byType(SecurityWarningBanner), findsOneWidget);
      // The protected content is still fully rendered (never blocked).
      expect(find.text('Vault Content'), findsOneWidget);
    });

    testWidgets('shows no banner for a clean device', (tester) async {
      final detector = FakeRootDetectionService(integrity: _clean);

      await tester.pumpWidget(
        MaterialApp(
          home: SecureScreenWrapper(
            secureFlagService: FakeSecureFlagService(),
            rootDetectionService: detector,
            child: const Text('Vault Content'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(detector.detectCalls, 1);
      expect(find.byType(SecurityWarningBanner), findsNothing);
      expect(find.text('Vault Content'), findsOneWidget);
    });

    testWidgets('runs no detection when no detector is injected',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SecureScreenWrapper(
            secureFlagService: FakeSecureFlagService(),
            child: const Text('Vault Content'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SecurityWarningBanner), findsNothing);
      expect(find.text('Vault Content'), findsOneWidget);
    });

    testWidgets(
        'gracefully degrades when FLAG_SECURE enable throws: content renders '
        'and no unhandled error escapes', (tester) async {
      final flag = FakeSecureFlagService()..throwOnEnable = true;

      await tester.pumpWidget(
        MaterialApp(
          home: SecureScreenWrapper(
            secureFlagService: flag,
            rootDetectionService: FakeRootDetectionService(integrity: _rooted),
            child: const Text('Vault Content'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(flag.enableCalls, 1);
      // The protected screen still renders and the warning still appears.
      expect(find.text('Vault Content'), findsOneWidget);
      expect(find.byType(SecurityWarningBanner), findsOneWidget);
    });

    testWidgets(
        'gracefully degrades when FLAG_SECURE disable throws on unmount',
        (tester) async {
      final flag = FakeSecureFlagService()..throwOnDisable = true;

      await tester.pumpWidget(
        MaterialApp(
          home: SecureScreenWrapper(
            secureFlagService: flag,
            child: const Text('War Room'),
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(flag.disableCalls, 1);
      // No unhandled exception escaped (test would otherwise fail).
    });
  });

  group('SecurityWarningBanner', () {
    testWidgets('renders the default warning copy', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SecurityWarningBanner())),
      );

      expect(find.byType(SecurityWarningBanner), findsOneWidget);
      expect(find.textContaining('rooted'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('renders custom message when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecurityWarningBanner(message: 'Custom caution message'),
          ),
        ),
      );

      expect(find.text('Custom caution message'), findsOneWidget);
    });
  });
}
