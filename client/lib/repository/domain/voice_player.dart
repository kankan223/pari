import 'dart:async';

/// Port for audio playback.
///
/// Implementations use just_audio on all platforms. The port abstracts
/// the player lifecycle so the UI can bind to position/duration streams.
abstract class VoicePlayer {
  /// Current playback position in milliseconds.
  Stream<Duration> get position;

  /// Total duration of the loaded audio.
  Stream<Duration?> get duration;

  /// Whether audio is currently playing.
  Stream<bool> get playing;

  /// Load audio bytes for playback.
  Future<void> load(List<int> bytes);

  /// Start or resume playback.
  Future<void> play();

  /// Pause playback.
  Future<void> pause();

  /// Stop and reset to beginning.
  Future<void> stop();

  /// Seek to a specific position.
  Future<void> seek(Duration position);

  /// Release resources.
  Future<void> dispose();
}
