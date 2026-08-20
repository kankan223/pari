import 'package:civic_commons/deployment/domain/build_config.dart';

import 'deployment_state.dart';

/// Port for the deployment BLoC (Task 14.1–14.4).
///
/// Provides a stream of [DeploymentState] and actions to trigger builds,
/// run verification, and check health.
abstract class DeploymentBloc {
  /// Current state stream.
  Stream<DeploymentState> get stream;

  /// Current state value.
  DeploymentState get state;

  /// Initialize with a build configuration.
  void initialize(EnvironmentConfig config);

  /// Run the CI/CD pipeline quality gates.
  void runPipeline();

  /// Run release verification checks.
  void runVerification();

  /// Refresh the health report.
  void refreshHealth();

  /// Reset all state to initial values.
  void reset();

  /// Close the bloc and release resources.
  void close();
}
