import 'duress_setup_state.dart';

/// BLoC for the duress PIN setup flow (Task 6.6 onboarding).
///
/// Registers the real + duress PIN pair via the [DuressService] and
/// exposes the lifecycle to the setup UI. The UI labels the two fields
/// (the user is choosing them during onboarding); everything AFTER this
/// screen treats the PINs identically — no real/duress indicator is ever
/// persisted, logged, or exposed through this BLoC.
abstract class DuressSetupBloc {
  /// Stream of setup states (idle → registering → registered/failed).
  Stream<DuressSetupState> get state;

  /// Starts the flow (idle).
  Future<void> start();

  /// Registers the [realPin]/[duressPin] pair.
  ///
  /// Throws [ArgumentError] for empty PINs and
  /// [DuressRegistrationException] for identical PINs or duplicate
  /// registration — the UI can present a generic failure via [state].
  Future<void> register({
    required String realPin,
    required String duressPin,
  });

  /// Releases resources.
  Future<void> close();
}
