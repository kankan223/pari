import 'dart:async';

import 'identity_api_client.dart';
import 'auth_storage.dart';

/// Authentication state machine for the login/registration flow.
///
/// Flow: initial → phoneEntry → otpSent → otpVerifying → otpVerified
///       → usernameEntry → registering → registered → authenticated
///
/// SECURITY: Phone numbers exist only transiently during the OTP request
/// call — they are never stored, logged, or emitted in state.
class AuthBloc {
  final IdentityApiClient _api;
  final AuthStorage _storage;

  final _stateController = StreamController<AuthState>.broadcast();
  AuthState _current = const AuthState.initial();

  AuthBloc({
    required IdentityApiClient api,
    required AuthStorage storage,
  })  : _api = api,
        _storage = storage;

  /// Current auth state.
  Stream<AuthState> get state => _stateController.stream;
  AuthState get current => _current;

  /// Initialize — check if already authenticated.
  ///
  /// If the user has a token but no username, they are shown the username
  /// entry screen (username claim is mandatory before accessing the app).
  Future<void> init() async {
    final isAuthenticated = await _storage.isAuthenticated();
    if (isAuthenticated) {
      final username = await _storage.getUsername();
      final blindHashId = await _storage.getBlindHashId();
      if (username != null && username.isNotEmpty) {
        _emit(AuthState.authenticated(
          username: username,
          blindHashId: blindHashId ?? '',
        ));
      } else {
        // Token exists but no username claimed yet — must claim one.
        _emit(AuthState.otpVerified(
          blindHashId: blindHashId ?? '',
        ));
      }
    } else {
      _emit(const AuthState.initial());
    }
  }

  /// Submit phone number to request OTP.
  Future<void> submitPhone(String phone) async {
    _emit(_current.copyWith(
      phase: AuthPhase.phoneSubmitting,
      error: null,
    ));

    try {
      final result = await _api.requestOtp(phone);
      _emit(AuthState.otpSent(
        blindHashId: result.blindHashId,
        devOtpCode: result.devOtpCode,
      ));
    } on IdentityApiException catch (e) {
      _emit(_current.copyWith(
        phase: AuthPhase.phoneEntry,
        error: e.message,
      ));
    } catch (e) {
      _emit(_current.copyWith(
        phase: AuthPhase.phoneEntry,
        error: 'Network error. Please try again.',
      ));
    }
  }

  /// Submit OTP code for verification.
  Future<void> submitOtp(String otp) async {
    final blindHashId = _current.blindHashId;
    if (blindHashId == null) return;

    _emit(_current.copyWith(
      phase: AuthPhase.otpVerifying,
      error: null,
    ));

    try {
      final result = await _api.verifyOtp(
        blindHashId: blindHashId,
        otp: otp,
      );

      // Save tokens.
      await _storage.saveAuthTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        blindHashId: blindHashId,
      );

      // Check if user already has a username.
      if (result.user?.username != null &&
          result.user!.username!.isNotEmpty) {
        await _storage.saveUsername(result.user!.username!);
        _emit(AuthState.authenticated(
          username: result.user!.username!,
          blindHashId: blindHashId,
        ));
      } else {
        _emit(AuthState.otpVerified(
          blindHashId: blindHashId,
        ));
      }
    } on IdentityApiException catch (e) {
      _emit(_current.copyWith(
        phase: AuthPhase.otpSent,
        blindHashId: blindHashId,
        error: e.message,
      ));
    } catch (e) {
      _emit(_current.copyWith(
        phase: AuthPhase.otpSent,
        blindHashId: blindHashId,
        error: 'Verification failed. Please try again.',
      ));
    }
  }

  /// Submit username for claiming.
  Future<void> submitUsername(String username) async {
    _emit(_current.copyWith(
      phase: AuthPhase.registering,
      error: null,
    ));

    try {
      final token = await _storage.getAccessToken();
      if (token == null) {
        throw StateError('No access token available');
      }

      await _api.claimUsername(
        accessToken: token,
        username: username,
      );

      await _storage.saveUsername(username);
      _emit(AuthState.authenticated(
        username: username,
        blindHashId: _current.blindHashId ?? '',
      ));
    } on IdentityApiException catch (e) {
      _emit(_current.copyWith(
        phase: AuthPhase.usernameEntry,
        error: e.message,
      ));
    } catch (e) {
      _emit(_current.copyWith(
        phase: AuthPhase.usernameEntry,
        error: 'Registration failed. Please try again.',
      ));
    }
  }

  /// Go back to the phone entry phase (e.g. "use a different number").
  void goToPhoneEntry() {
    _emit(const AuthState.initial());
  }

  /// Logout — clear all auth state.
  Future<void> logout() async {
    await _storage.clearAll();
    _emit(const AuthState.initial());
  }

  void _emit(AuthState newState) {
    _current = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _stateController.close();
  }
}

/// Authentication phases.
enum AuthPhase {
  initial,
  phoneEntry,
  phoneSubmitting,
  otpSent,
  otpVerifying,
  otpVerified,
  usernameEntry,
  registering,
  authenticated,
}

/// Immutable authentication state.
class AuthState {
  final AuthPhase phase;
  final String? blindHashId;
  final String? username;
  final String? error;
  /// Dev-only: plaintext OTP code returned by the identity service in staging.
  final String? devOtpCode;

  const AuthState({
    required this.phase,
    this.blindHashId,
    this.username,
    this.error,
    this.devOtpCode,
  });

  const AuthState.initial() : this(phase: AuthPhase.initial);

  const AuthState.phoneEntry()
      : this(phase: AuthPhase.phoneEntry);

  const AuthState.otpSent({
    required String blindHashId,
    String? devOtpCode,
  }) : this(
          phase: AuthPhase.otpSent,
          blindHashId: blindHashId,
          devOtpCode: devOtpCode,
        );

  const AuthState.otpVerified({required String blindHashId})
      : this(phase: AuthPhase.otpVerified, blindHashId: blindHashId);

  const AuthState.authenticated({
    required String username,
    required String blindHashId,
  }) : this(
          phase: AuthPhase.authenticated,
          username: username,
          blindHashId: blindHashId,
        );

  AuthState copyWith({
    AuthPhase? phase,
    String? blindHashId,
    String? username,
    String? error,
    String? devOtpCode,
  }) {
    return AuthState(
      phase: phase ?? this.phase,
      blindHashId: blindHashId ?? this.blindHashId,
      username: username ?? this.username,
      error: error,
      devOtpCode: devOtpCode ?? this.devOtpCode,
    );
  }

  bool get isInitial => phase == AuthPhase.initial;
  bool get isPhoneEntry => phase == AuthPhase.phoneEntry;
  bool get isPhoneSubmitting => phase == AuthPhase.phoneSubmitting;
  bool get isOtpSent => phase == AuthPhase.otpSent;
  bool get isOtpVerifying => phase == AuthPhase.otpVerifying;
  bool get isOtpVerified => phase == AuthPhase.otpVerified;
  bool get isUsernameEntry => phase == AuthPhase.usernameEntry;
  bool get isRegistering => phase == AuthPhase.registering;
  bool get isAuthenticated => phase == AuthPhase.authenticated;
  bool get hasError => error != null;
  bool get isLoading =>
      phase == AuthPhase.phoneSubmitting ||
      phase == AuthPhase.otpVerifying ||
      phase == AuthPhase.registering;
}
