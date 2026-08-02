import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/security/data/method_channel_secure_flag_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MethodChannelSecureFlagService.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isSecureFlagSupported':
          return true;
        case 'enableSecureFlag':
        case 'disableSecureFlag':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('MethodChannelSecureFlagService', () {
    test('isSecureFlagSupported returns true when the native side supports it',
        () async {
      final service = MethodChannelSecureFlagService();

      final supported = await service.isSecureFlagSupported();

      expect(supported, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'isSecureFlagSupported');
    });

    test('enableSecureFlag invokes the enable method on the channel',
        () async {
      final service = MethodChannelSecureFlagService();

      await service.enableSecureFlag();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'enableSecureFlag');
    });

    test('disableSecureFlag invokes the disable method on the channel',
        () async {
      final service = MethodChannelSecureFlagService();

      await service.disableSecureFlag();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'disableSecureFlag');
    });

    test('returns false instead of throwing when the plugin is missing',
        () async {
      messenger.setMockMethodCallHandler(channel, null);
      final service = MethodChannelSecureFlagService();

      expect(await service.isSecureFlagSupported(), isFalse);
      // No-op rather than throwing:
      await service.enableSecureFlag();
      await service.disableSecureFlag();
    });

    test('isSecureFlagSupported returns false when native reports false',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      final service = MethodChannelSecureFlagService();

      expect(await service.isSecureFlagSupported(), isFalse);
    });
  });
}
