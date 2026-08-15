import 'package:flutter/services.dart';

import '../domain/secure_flag_service.dart';

/// Platform-channel implementation of [SecureFlagService].
///
/// Talks to the Android native side over the `civic_commons/secure_flag`
/// channel. The native side (see the documented reference below) toggles the
/// `FLAG_SECURE` window flag so the protected screen cannot be captured.
///
/// Reference native wiring (Android, `MainActivity`/`MainApplication`):
/// ```kotlin
/// class MainActivity : FlutterActivity() {
///   override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
///     super.configureFlutterEngine(flutterEngine)
///     MethodChannel(
///       flutterEngine.dartExecutor.binaryMessenger,
///       "civic_commons/secure_flag",
///     ).setMethodCallHandler { call, result ->
///       when (call.method) {
///         "isSecureFlagSupported" -> result.success(true)
///         "enableSecureFlag" -> {
///           window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
///           result.success(null)
///         }
///         "disableSecureFlag" -> {
///           window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
///           result.success(null)
///         }
///         else -> result.notImplemented()
///       }
///     }
///   }
/// }
/// ```
///
/// Security contract:
/// - FLAG_SECURE is a local OS window flag; no content or device data is ever
///   transmitted.
/// - If the native channel is absent (e.g. unit tests, other platforms),
///   every call degrades gracefully to a no-op instead of throwing.
class MethodChannelSecureFlagService implements SecureFlagService {
  /// Channel name — must match the native registration exactly.
  static const String channelName = 'civic_commons/secure_flag';

  final MethodChannel _channel;

  MethodChannelSecureFlagService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  @override
  Future<bool> isSecureFlagSupported() async {
    try {
      final supported =
          await _channel.invokeMethod<bool>('isSecureFlagSupported');
      return supported ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> enableSecureFlag() async {
    try {
      await _channel.invokeMethod<void>('enableSecureFlag');
    } on MissingPluginException {
      // Unsupported platform — protected screens still render (degraded).
    }
  }

  @override
  Future<void> disableSecureFlag() async {
    try {
      await _channel.invokeMethod<void>('disableSecureFlag');
    } on MissingPluginException {
      // Unsupported platform — nothing to clear.
    }
  }
}
