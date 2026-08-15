/// Severity of a log entry.
///
/// Ordered from most to least verbose: [debug] < [info] < [warning] < [error].
enum LogLevel {
  /// Verbose diagnostics — development only, never emitted in production.
  debug,

  /// Routine operational information.
  info,

  /// Something went wrong but the app can continue.
  warning,

  /// A failure occurred; details are still redacted.
  error,
}

/// Configuration of which levels are emitted in a given environment.
///
/// SECURITY: the production configuration never emits [LogLevel.debug] so
/// verbose diagnostics (which are the most likely to carry accidental
/// payloads) are structurally excluded in shipped builds.
class LogLevelConfig {
  final String environment;
  final LogLevel minimumLevel;

  const LogLevelConfig({
    required this.environment,
    required this.minimumLevel,
  });

  /// Development: everything is logged.
  static const LogLevelConfig development = LogLevelConfig(
    environment: 'development',
    minimumLevel: LogLevel.debug,
  );

  /// Production: only info and above; debug is never emitted.
  static const LogLevelConfig production = LogLevelConfig(
    environment: 'production',
    minimumLevel: LogLevel.info,
  );

  /// Returns true if [level] passes the configured minimum.
  bool shouldEmit(LogLevel level) => level.index >= minimumLevel.index;
}
