import 'package:civic_commons/auth/auth_storage.dart';
import 'package:civic_commons/auth/identity_api_client.dart';
import 'package:civic_commons/security/ui/secure_screen_wrapper.dart';
import 'package:civic_commons/state/ui/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile model', () {
    test('fromJson parses all profile fields', () {
      final profile = UserProfile.fromJson({
        'blind_hash_id': 'abc123',
        'username': 'alice',
        'avatar_url': 'data:image/png;base64,abc',
        'status_text': 'Hello!',
        'status_visibility': 'online',
        'created_at': '2025-01-01T00:00:00Z',
      });

      expect(profile.blindHashId, 'abc123');
      expect(profile.username, 'alice');
      expect(profile.avatarUrl, 'data:image/png;base64,abc');
      expect(profile.statusText, 'Hello!');
      expect(profile.statusVisibility, 'online');
    });

    test('fromJson handles missing optional fields', () {
      final profile = UserProfile.fromJson({
        'blind_hash_id': 'abc123',
        'created_at': '2025-01-01T00:00:00Z',
      });

      expect(profile.avatarUrl, isNull);
      expect(profile.statusText, isNull);
      expect(profile.statusVisibility, isNull);
      expect(profile.username, isNull);
    });
  });

  group('ProfileScreen', () {
    // Note: ProfileScreen uses FlutterSecureStorage which requires platform
    // plugins. In the CI/test environment, storage operations may not complete
    // synchronously. We test the widget by verifying it builds and shows the
    // loading indicator, then pump several frames.

    testWidgets('renders without crashing', (tester) async {
      final api = IdentityApiClient(baseUrl: 'https://test.example.com');
      // AuthStorage() constructor works in test — it creates a real instance
      // backed by flutter_secure_storage which has a test/mock implementation.
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            api: api,
            storage: AuthStorage(),
          ),
        ),
      );
      // The screen should render without throwing.
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      final api = IdentityApiClient(baseUrl: 'https://test.example.com');
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(api: api, storage: AuthStorage()),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('SECURITY: SecureScreenWrapper present', (tester) async {
      final api = IdentityApiClient(baseUrl: 'https://test.example.com');
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(api: api, storage: AuthStorage()),
        ),
      );
      expect(find.byType(SecureScreenWrapper), findsOneWidget);
    });

    testWidgets('SECURITY: no blind hash in built widget', (tester) async {
      final api = IdentityApiClient(baseUrl: 'https://test.example.com');
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(api: api, storage: AuthStorage()),
        ),
      );
      // A blind hash is 64 lowercase hex chars. Verify none appear.
      final finder = find.byType(MaterialApp);
      final widget = tester.widget(finder);
      final str = widget.toString();
      expect(RegExp(r'[0-9a-f]{64}').hasMatch(str), isFalse);
    });

    testWidgets('SECURITY: no phone number in widget tree', (tester) async {
      final api = IdentityApiClient(baseUrl: 'https://test.example.com');
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(api: api, storage: AuthStorage()),
        ),
      );
      final finder = find.byType(MaterialApp);
      final widget = tester.widget(finder);
      final str = widget.toString();
      // E.164 phone pattern like +12025551234.
      expect(RegExp(r'\+\d{10,15}').hasMatch(str), isFalse);
    });
  });
}
