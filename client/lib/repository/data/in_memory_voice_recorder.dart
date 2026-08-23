import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../domain/voice_recorder.dart';

/// In-memory voice recorder that simulates recording for dev/test.
///
/// On web and desktop, the real `record` package requires platform
/// permissions. This fake produces deterministic silence bytes so the
/// UI flow can be exercised without microphone access.
class InMemoryVoiceRecorder implements VoiceRecorder {
  bool _recording = false;
  final _amplitudeController = StreamController<double>.broadcast();
  Timer? _amplitudeTimer;

  @override
  bool get isRecording => _recording;

  @override
  Stream<double> get amplitude => _amplitudeController.stream;

  @override
  Future<void> start() async {
    if (_recording) return;
    _recording = true;
    // Simulate amplitude fluctuations.
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_recording) return;
      _amplitudeController.add(Random().nextDouble() * 0.5 + 0.1);
    });
  }

  @override
  Future<Uint8List> stop() async {
    if (!_recording) return Uint8List(0);
    _recording = false;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    // Return fake audio bytes (silence — dev/test only).
    return Uint8List(1024);
  }

  @override
  Future<void> cancel() async {
    _recording = false;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _amplitudeController.close();
  }
}
