import 'dart:async';
import 'dart:typed_data';

/// Port for audio recording.
///
/// Implementations use platform-specific recording APIs (record package
/// on mobile/desktop, MediaRecorder on web). The port abstracts the
/// platform details so the domain layer stays platform-agnostic.
abstract class VoiceRecorder {
  /// Whether the recorder is currently recording.
  bool get isRecording;

  /// Start recording audio. Throws if already recording.
  Future<void> start();

  /// Stop recording and return the audio bytes.
  Future<Uint8List> stop();

  /// Cancel the current recording without returning bytes.
  Future<void> cancel();

  /// Stream of recording amplitude levels (0.0 to 1.0) for waveform UI.
  Stream<double> get amplitude;

  /// Release resources.
  Future<void> dispose();
}
