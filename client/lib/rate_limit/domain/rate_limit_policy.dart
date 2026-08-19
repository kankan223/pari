/// Fixed rate limiting policies for the Rate Limiting & Abuse Prevention
/// system (Task 11.3).
///
/// Each policy defines the window size, maximum request count, and cooldown
/// duration for a specific action type. The labels are fixed, non-sensitive,
/// and carry no PII.
///
/// SECURITY CHECKPOINT (11.3): policies carry NO identity, NO phone
/// numbers, NO payload content — they are fixed, compile-time-known
/// configurations only.
enum RateLimitPolicy {
  /// OTP request: 5 requests per 10-minute sliding window.
  otpRequest(
    label: 'OTP Request',
    maxRequests: 5,
    windowSeconds: 600,
    cooldownSeconds: 900,
  ),

  /// Login attempt: 10 attempts per 15-minute sliding window.
  loginAttempt(
    label: 'Login Attempt',
    maxRequests: 10,
    windowSeconds: 900,
    cooldownSeconds: 1800,
  ),

  /// Username claim: 3 attempts per hour.
  usernameClaim(
    label: 'Username Claim',
    maxRequests: 3,
    windowSeconds: 3600,
    cooldownSeconds: 7200,
  ),

  /// Connection request: 10 requests per hour.
  connectionRequest(
    label: 'Connection Request',
    maxRequests: 10,
    windowSeconds: 3600,
    cooldownSeconds: 3600,
  ),

  /// Post creation: 20 posts per hour.
  postCreation(
    label: 'Post Creation',
    maxRequests: 20,
    windowSeconds: 3600,
    cooldownSeconds: 1800,
  ),

  /// Vote action: 100 votes per hour.
  voteAction(
    label: 'Vote Action',
    maxRequests: 100,
    windowSeconds: 3600,
    cooldownSeconds: 900,
  ),

  /// API mutation: 30 mutations per 5-minute sliding window.
  apiMutation(
    label: 'API Mutation',
    maxRequests: 30,
    windowSeconds: 300,
    cooldownSeconds: 600,
  ),

  /// General action: 60 actions per minute.
  generalAction(
    label: 'General Action',
    maxRequests: 60,
    windowSeconds: 60,
    cooldownSeconds: 120,
  );

  const RateLimitPolicy({
    required this.label,
    required this.maxRequests,
    required this.windowSeconds,
    required this.cooldownSeconds,
  });

  /// Fixed, non-sensitive classification label rendered in the viewer.
  final String label;

  /// Maximum number of requests allowed within the sliding window.
  final int maxRequests;

  /// Duration of the sliding window in seconds.
  final int windowSeconds;

  /// Cooldown duration in seconds after the limit is exceeded.
  final int cooldownSeconds;

  /// Parse from a wire string; throws [FormatException] on unknown codes.
  static RateLimitPolicy fromWireName(String wire) {
    return RateLimitPolicy.values.firstWhere(
      (p) => p.name == wire,
      orElse: () => throw FormatException('Unknown rate limit policy: $wire'),
    );
  }
}
