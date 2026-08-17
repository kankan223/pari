import 'package:flutter/material.dart';

import '../../identity/civic_pillar.dart';
import '../../identity/pillar_claim.dart';
import '../../identity/pillar_claims.dart';
import '../../security/domain/secure_flag_service.dart';
import '../../security/ui/secure_screen_wrapper.dart';
import '../domain/identity_verification_bloc.dart';
import '../domain/identity_verification_state.dart';

/// The one-time onboarding identity verification screen (Task 10.1 —
/// Unified Identity Layer).
///
/// Shows the user that ONE blind-hash identity is shared read-only across
/// all four pillars, with the MINIMUM claim each pillar holds (PRD §9.1):
///
///   🔒 The Vault      → username, device keys
///   📰 The Ledger     → pin code, karma
///   🛡  The War Room  → nothing beyond the hash
///   🎓 The Academy   → nothing beyond the hash
///
/// SECURITY CHECKPOINT (Task 10.1): the screen renders ONLY the blinded
/// `@citizen_` handle (never the full 64-hex blind hash), fixed pillar
/// labels, and the claim chips for the VERIFIED state. No phone, no raw
/// hash, no username outside the Vault claim, no full profile ever appears
/// in the widget tree. Wrapped in [SecureScreenWrapper] (FLAG_SECURE).
class IdentityVerificationScreen extends StatefulWidget {
  /// The verification BLoC (injected — never constructed here).
  final IdentityVerificationBloc bloc;

  /// Injectable FLAG_SECURE service (test seam) — null uses the production
  /// default.
  final SecureFlagService? secureFlagService;

  /// Optional host seam: when the user confirms verification, the host can
  /// navigate away (e.g. to the app shell).
  final VoidCallback? onVerified;

  const IdentityVerificationScreen({
    super.key,
    required this.bloc,
    this.secureFlagService,
    this.onVerified,
  });

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> {
  IdentityVerificationState? _last;

  @override
  void initState() {
    super.initState();
    _last = widget.bloc.current;
    widget.bloc.state.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() => _last = state);
    });
    // Start the verification on mount.
    widget.bloc.verify();
  }

  Widget _secure(Widget child) {
    final flag = widget.secureFlagService;
    return flag == null
        ? SecureScreenWrapper(child: child)
        : SecureScreenWrapper(secureFlagService: flag, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final state = _last ?? const IdentityVerificationState.idle();
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6ED),
      body: _secure(
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _IdentityMasthead(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _body(state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(IdentityVerificationState state) {
    if (state.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (state.isNoIdentity) {
      return const _NoIdentityCard();
    }
    if (state.isError) {
      return _ErrorCard(message: state.errorMessage ?? 'Something went wrong');
    }
    if (state.isVerified) {
      return _VerifiedCard(
        handle: state.displayHandle,
        claims: state.pillarClaims,
        onVerified: widget.onVerified,
      );
    }
    return const SizedBox.shrink();
  }
}

/// Fixed identity masthead (blinded handle + fixed labels only).
class _IdentityMasthead extends StatelessWidget {
  const _IdentityMasthead();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1F2430),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '❧ CIVIC COMMONS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'ONE IDENTITY · FOUR PILLARS',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              letterSpacing: 1.6,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Verified state: the blinded handle + one row per pillar with its claim
/// chips.
class _VerifiedCard extends StatelessWidget {
  final String handle;
  final Map<CivicPillar, dynamic> claims;
  final VoidCallback? onVerified;

  const _VerifiedCard({
    required this.handle,
    required this.claims,
    this.onVerified,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE3DCC8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'IDENTITY VERIFIED',
                style: TextStyle(
                  color: Color(0xFF2F6B4F),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You participate across Civic Commons as',
                style: TextStyle(
                  color: Color(0xFF6E6A5E),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                handle,
                style: const TextStyle(
                  color: Color(0xFF1F2430),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'One blind hash — shared read-only. Each pillar sees only the '
                'minimum it needs. No pillar holds your full profile.',
                style: TextStyle(
                  color: Color(0xFF6E6A5E),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'YOUR PILLAR ACCESS',
          style: TextStyle(
            color: Color(0xFF1F2430),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        for (final pillar in CivicPillar.values)
          _PillarClaimRow(
            pillar: pillar,
            claims: claims[pillar] as PillarClaims?,
          ),
        if (onVerified != null) ...[
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onVerified,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2F6B4F),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'CONTINUE TO CIVIC COMMONS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One row per pillar: fixed label + claim chips (only for the claims the
/// pillar actually holds — zero identity, zero payload).
class _PillarClaimRow extends StatelessWidget {
  final CivicPillar pillar;
  final PillarClaims? claims;

  const _PillarClaimRow({required this.pillar, required this.claims});

  String get _label => switch (pillar) {
        CivicPillar.vault => '🔒  The Vault',
        CivicPillar.ledger => '📰  The Daily Ledger',
        CivicPillar.warRoom => '🛡  The War Room',
        CivicPillar.academy => '🎓  The Academy',
      };

  List<String> get _chips {
    final c = claims;
    if (c == null) {
      return const ['identity only'];
    }
    final names = <String>[];
    for (final claim in c.heldClaims) {
      names.add(switch (claim) {
        PillarClaim.username => 'username',
        PillarClaim.deviceKeys => 'device keys',
        PillarClaim.pinCode => 'pin code',
        PillarClaim.karma => 'karma',
      });
    }
    // A pillar with NO extra claims still gets the 'identity only' chip
    // (War Room / Academy — the shared hash is the only claim).
    if (names.isEmpty) {
      return const ['identity only'];
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE3DCC8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _label,
              style: const TextStyle(
                color: Color(0xFF1F2430),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final chip in _chips)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2F6B4F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                chip,
                style: const TextStyle(
                  color: Color(0xFF2F6B4F),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// No-identity state: the device has no blind hash yet — the onboarding
/// phone flow must run first (generic copy, zero payload).
class _NoIdentityCard extends StatelessWidget {
  const _NoIdentityCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE3DCC8)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NO IDENTITY YET',
            style: TextStyle(
              color: Color(0xFF1F2430),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Verify your phone number to create your Civic Commons identity. '
            'Your number is converted to a code immediately and never stored.',
            style: TextStyle(
              color: Color(0xFF6E6A5E),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Generic error state — never a payload, never internal detail.
class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB3261E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'VERIFICATION UNAVAILABLE',
            style: TextStyle(
              color: Color(0xFFB3261E),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF6E6A5E),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
