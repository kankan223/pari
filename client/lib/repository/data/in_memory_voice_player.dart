import 'dart:async';

import '../domain/voice_player.dart';

/// In-memory voice player that simulates playback for dev/test.
///
/// Simulates a fixed-duration playback with ticking position updates
/// so the UI waveform/progress can be exercised without real audio.
class InMemoryVoicePlayer implements VoicePlayer {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playingController = StreamController<bool>.broadcast();

  Timer? _tickTimer;
  Duration _position = Duration.zero;
  Duration _totalDuration = const Duration(seconds: 5);
  bool _isPlaying = false;

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Stream<Duration?> get duration => _durationController.stream;

  @override
  Stream<bool> get playing => _playingController.stream;

  @override
  Future<void> load(List<int> bytes) async {
    // Simulate duration based on byte size (rough heuristic).
    _totalDuration = Duration(seconds: (bytes.length / 1000).ceil().clamp(1, 30));
    _position = Duration.zero;
    _durationController.add(_totalDuration);
    _positionController.add(_position);
  }

  @override
  Future<void> play() async {
    if (_isPlaying) return;
    _isPlaying = true;
    _playingController.add(true);
    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _position += const Duration(milliseconds: 100);
      if (_position >= _totalDuration) {
        _position = _totalDuration;
        stop();
        return;
      }
      _positionController.add(_position);
    });
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    _playingController.add(false);
  }

  @override
  Future<void> stop() async {
    _isPlaying = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    _position = Duration.zero;
    _playingController.add(false);
    _positionController.add(_position);
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionController.add(_position);
  }

  @override
  Future<void> dispose() async {
    _tickTimer?.cancel();
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
  }
}
