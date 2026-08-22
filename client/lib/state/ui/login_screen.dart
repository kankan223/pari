import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_bloc.dart';
import '../../identity/phone_validator.dart';
import '../../security/ui/secure_screen_wrapper.dart';

/// Country code data for the dropdown.
class _CountryCode {
  final String code;
  final String name;
  final String dialCode;
  final String flag;

  const _CountryCode(this.code, this.name, this.dialCode, this.flag);
}

/// List of common country codes.
const _countryCodes = [
  _CountryCode('IN', 'India', '+91', '🇮🇳'),
  _CountryCode('US', 'United States', '+1', '🇺🇸'),
  _CountryCode('GB', 'United Kingdom', '+44', '🇬🇧'),
  _CountryCode('CA', 'Canada', '+1', '🇨🇦'),
  _CountryCode('AU', 'Australia', '+61', '🇦🇺'),
  _CountryCode('DE', 'Germany', '+49', '🇩🇪'),
  _CountryCode('FR', 'France', '+33', '🇫🇷'),
  _CountryCode('JP', 'Japan', '+81', '🇯🇵'),
  _CountryCode('BR', 'Brazil', '+55', '🇧🇷'),
  _CountryCode('NG', 'Nigeria', '+234', '🇳🇬'),
  _CountryCode('ZA', 'South Africa', '+27', '🇿🇦'),
  _CountryCode('KE', 'Kenya', '+254', '🇰🇪'),
  _CountryCode('PH', 'Philippines', '+63', '🇵🇭'),
  _CountryCode('ID', 'Indonesia', '+62', '🇮🇩'),
  _CountryCode('PK', 'Pakistan', '+92', '🇵🇰'),
  _CountryCode('BD', 'Bangladesh', '+880', '🇧🇩'),
  _CountryCode('LK', 'Sri Lanka', '+94', '🇱🇰'),
  _CountryCode('NP', 'Nepal', '+977', '🇳🇵'),
  _CountryCode('AE', 'UAE', '+971', '🇦🇪'),
  _CountryCode('SA', 'Saudi Arabia', '+966', '🇸🇦'),
  _CountryCode('SG', 'Singapore', '+65', '🇸🇬'),
  _CountryCode('MY', 'Malaysia', '+60', '🇲🇾'),
  _CountryCode('TH', 'Thailand', '+66', '🇹🇭'),
  _CountryCode('VN', 'Vietnam', '+84', '🇻🇳'),
  _CountryCode('MX', 'Mexico', '+52', '🇲🇽'),
  _CountryCode('AR', 'Argentina', '+54', '🇦🇷'),
  _CountryCode('CO', 'Colombia', '+57', '🇨🇴'),
  _CountryCode('CL', 'Chile', '+56', '🇨🇱'),
  _CountryCode('EG', 'Egypt', '+20', '🇪🇬'),
  _CountryCode('GH', 'Ghana', '+233', '🇬🇭'),
  _CountryCode('TZ', 'Tanzania', '+255', '🇹🇿'),
  _CountryCode('ET', 'Ethiopia', '+251', '🇪🇹'),
  _CountryCode('MM', 'Myanmar', '+95', '🇲🇲'),
  _CountryCode('KR', 'South Korea', '+82', '🇰🇷'),
  _CountryCode('TR', 'Turkey', '+90', '🇹🇷'),
  _CountryCode('PL', 'Poland', '+48', '🇵🇱'),
  _CountryCode('IT', 'Italy', '+39', '🇮🇹'),
  _CountryCode('ES', 'Spain', '+34', '🇪🇸'),
  _CountryCode('NL', 'Netherlands', '+31', '🇳🇱'),
  _CountryCode('SE', 'Sweden', '+46', '🇸🇪'),
];

/// Login/registration screen for Civic Commons.
///
/// Shows a multi-step flow:
/// 1. Select country code + enter phone number
/// 2. Enter OTP code
/// 3. Set username (optional)
///
/// SECURITY CHECKPOINT: the screen is wrapped in [SecureScreenWrapper]
/// (FLAG_SECURE). Phone numbers exist only transiently during the OTP
/// request — they are never stored, logged, or displayed after submission.
class LoginScreen extends StatefulWidget {
  final AuthBloc authBloc;

  const LoginScreen({super.key, required this.authBloc});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  final _otpFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();

  _CountryCode _selectedCountry = _countryCodes[0]; // Default: India
  AuthState? _last;

  @override
  void initState() {
    super.initState();
    _last = widget.authBloc.current;
    widget.authBloc.state.listen((state) {
      if (mounted) setState(() => _last = state);
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _usernameController.dispose();
    _phoneFocusNode.dispose();
    _otpFocusNode.dispose();
    _usernameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _last ?? const AuthState.initial();
    return SecureScreenWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F0E8),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),
                // Logo + title
                const Icon(Icons.shield, size: 64, color: Color(0xFF1F4D3A)),
                const SizedBox(height: 16),
                const Text(
                  'Civic Commons',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F4D3A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _subtitleForPhase(state.phase),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6E6A5E),
                  ),
                ),
                const SizedBox(height: 40),
                // Body based on phase
                _buildBody(state),
                // Error message
                if (state.hasError) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDECEA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFB3261E)),
                    ),
                    child: Text(
                      state.error!,
                      style: const TextStyle(
                        color: Color(0xFFB3261E),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitleForPhase(AuthPhase phase) {
    return switch (phase) {
      AuthPhase.initial || AuthPhase.phoneEntry || AuthPhase.phoneSubmitting =>
        'Verify your phone to get started',
      AuthPhase.otpSent || AuthPhase.otpVerifying =>
        'Enter the code sent to your phone',
      AuthPhase.otpVerified || AuthPhase.usernameEntry || AuthPhase.registering =>
        'Choose a username for the community',
      AuthPhase.authenticated => 'Welcome back!',
    };
  }

  Widget _buildBody(AuthState state) {
    if (state.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: Color(0xFF1F4D3A)),
        ),
      );
    }

    if (state.isOtpSent || state.isOtpVerifying) {
      return _buildOtpStep(state);
    }

    if (state.isOtpVerified || state.isUsernameEntry || state.isRegistering) {
      return _buildUsernameStep(state);
    }

    // Default: phone entry
    return _buildPhoneStep(state);
  }

  Widget _buildPhoneStep(AuthState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'PHONE NUMBER',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1F2430),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        // Country code dropdown + phone number field
        Row(
          children: [
            // Country code dropdown
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD4CFC0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_CountryCode>(
                  value: _selectedCountry,
                  isDense: true,
                  items: _countryCodes.map((c) {
                    return DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${c.flag} ${c.dialCode}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedCountry = v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Phone number field
            Expanded(
              child: TextField(
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '98765 43210',
                  hintStyle: const TextStyle(color: Colors.black38),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFD4CFC0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: Color(0xFF1F4D3A), width: 2),
                  ),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ],
                onSubmitted: (_) => _submitPhone(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Your number is converted to a code immediately and never stored.',
          style: TextStyle(
            fontSize: 11,
            color: const Color(0xFF6E6A5E),
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: state.isPhoneSubmitting ? null : _submitPhone,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1F4D3A),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'SEND VERIFICATION CODE',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep(AuthState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'CODE SENT',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1F2430),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _otpController,
          focusNode: _otpFocusNode,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            hintText: '000000',
            hintStyle: const TextStyle(color: Colors.black38),
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD4CFC0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                  color: Color(0xFF1F4D3A), width: 2),
            ),
            prefixIcon: const Icon(Icons.lock_outline,
                color: Color(0xFF1F4D3A)),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: const TextStyle(
            fontSize: 24,
            letterSpacing: 8,
            fontFamily: 'monospace',
          ),
          textAlign: TextAlign.center,
          onSubmitted: (_) => _submitOtp(),
        ),
        const SizedBox(height: 12),
        // Dev OTP code display (only shown in staging mode)
        if ((state.devOtpCode ?? '').isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF7B1FA2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.developer_mode, size: 20, color: Color(0xFF7B1FA2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DEV MODE - Your OTP code:',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7B1FA2),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.devOtpCode!,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF7B1FA2),
                          letterSpacing: 8,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Color(0xFF2E7D32)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Check your phone for the 6-digit code. '
                    'It may take a minute to arrive.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: state.isOtpVerifying ? null : _submitOtp,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1F4D3A),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'VERIFY CODE',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            _otpController.clear();
            // Go back to phone entry — just reset the phase, don't call the API
            // with an empty phone number.
            widget.authBloc.goToPhoneEntry();
          },
          child: const Text(
            'Use a different number',
            style: TextStyle(color: Color(0xFF1F4D3A)),
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameStep(AuthState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'CHOOSE A USERNAME',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1F2430),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _usernameController,
          focusNode: _usernameFocusNode,
          decoration: InputDecoration(
            hintText: 'e.g. civic_watcher',
            hintStyle: const TextStyle(color: Colors.black38),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD4CFC0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                  color: Color(0xFF1F4D3A), width: 2),
            ),
            prefixIcon: const Icon(Icons.person_outline,
                color: Color(0xFF1F4D3A)),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
            LengthLimitingTextInputFormatter(30),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitUsername(),
        ),
        const SizedBox(height: 8),
        const Text(
          '3–30 lowercase letters, numbers, or underscores. '
          'This is your public identity across all pillars.',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF6E6A5E),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: state.isRegistering ? null : _submitUsername,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1F4D3A),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'CLAIM USERNAME & ENTER',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Username is required to message other users.',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF6E6A5E),
          ),
        ),
      ],
    );
  }

  void _submitPhone() {
    final phoneDigits = _phoneController.text.trim();
    if (phoneDigits.isEmpty) {
      setState(() {
        _last = _last?.copyWith(
          error: 'Please enter your phone number',
        );
      });
      return;
    }

    // Build full E.164 number from dropdown + digits
    final phone = '${_selectedCountry.dialCode}$phoneDigits';

    if (!PhoneValidator.isValidE164(phone)) {
      setState(() {
        _last = _last?.copyWith(
          error: 'Please enter a valid phone number',
        );
      });
      return;
    }

    // SECURITY: phone exists only in this call — after requestOtp returns,
    // the controller will be cleared and the variable goes out of scope.
    widget.authBloc.submitPhone(phone);
    _phoneController.clear();
    _otpFocusNode.requestFocus();
  }

  void _submitOtp() {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() {
        _last = _last?.copyWith(
          error: 'Please enter the 6-digit code',
        );
      });
      return;
    }
    widget.authBloc.submitOtp(otp);
    _otpController.clear();
  }

  void _submitUsername() {
    final username = _usernameController.text.trim().toLowerCase();
    if (username.length < 3) {
      setState(() {
        _last = _last?.copyWith(
          error: 'Username must be at least 3 characters',
        );
      });
      return;
    }
    if (!RegExp(r'^[a-z][a-z0-9_]{2,29}$').hasMatch(username)) {
      setState(() {
        _last = _last?.copyWith(
          error: 'Username must start with a letter, use only a-z, 0-9, _',
        );
      });
      return;
    }
    widget.authBloc.submitUsername(username);
    _usernameController.clear();
  }
}
