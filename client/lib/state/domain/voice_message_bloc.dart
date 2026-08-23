import 'dart:async';
import 'dart:typed_data';

import '../../repository/domain/voice_message.dart';
import '../../repository/domain/voice_player.dart';
import '../../repository/domain/voice_recorder.dart';

/// BLoC for voice message recording and playback in a conversation.
///
/// Manages the recording lifecycle (start → stop → send) and playback
/// state (load → play → pause → stop) for voice bubbles.
///
/// SECURITY CHECKPOINT: voice bytes are encrypted before leaving the
/// device. No identity, phone number, or PII is attached to recordings.
class VoiceMessageBloc {
  final VoiceRecorder _recorder;
  final VoicePlayer _player;

  final _controller = StreamController<VoiceMessageState>.broadcast();
  VoiceMessageState _state = const VoiceMessageState();
  StreamSubscription<double>? _amplitudeSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<bool>? _playingSub;

  VoiceMessageBloc({
    required VoiceRecorder recorder,
    required VoicePlayer player,
  })  : _recorder = recorder,
        _player = player;

  Stream<VoiceMessageState> get state => _controller.stream;
  VoiceMessageState get currentState => _state;

  /// Start listening to recorder and player streams.
  void start() {
    _amplitudeSub = _recorder.amplitude.listen((level) {
      _state = _state.copyWith(amplitudeLevels: [
        ..._state.amplitudeLevels,
        level,
      ]);
      _emit();
    });

    _positionSub = _player.position.listen((pos) {
      _state = _state.copyWith(playbackPosition: pos);
      _emit();
    });

    _durationSub = _player.duration.listen((dur) {
      _state = _state.copyWith(playbackDuration: dur);
      _emit();
    });

    _playingSub = _player.playing.listen((playing) {
      _state = _state.copyWith(isPlaying: playing);
      _emit();
    });
  }

  /// Start recording a voice message.
  Future<void> startRecording() async {
    _state = _state.copyWith(
      isRecording: true,
      amplitudeLevels: [],
      recordingDuration: Duration.zero,
    );
    _emit();
    await _recorder.start();
  }

  /// Stop recording and return the audio bytes.
  /// Returns null if no recording was active.
  Future<Uint8List?> stopRecording() async {
    if (!_state.isRecording) return null;
    final bytes = await _recorder.stop();
    final duration = _state.recordingDuration;
    _state = _state.copyWith(
      isRecording: false,
      recordedBytes: bytes,
      recordingDuration: duration,
    );
    _emit();
    return bytes;
  }

  /// Cancel the current recording.
  Future<void> cancelRecording() async {
    await _recorder.cancel();
    _state = _state.copyWith(
      isRecording: false,
      recordedBytes: null,
      amplitudeLevels: [],
    );
    _emit();
  }

  /// Load and play a voice message from encrypted bytes.
  Future<void> playMessage(VoiceMessage message) async {
    await _player.load(message.encryptedBytes);
    await _player.play();
  }

  /// Pause the current playback.
  Future<void> pausePlayback() async => _player.pause();

  /// Stop the current playback.
  Future<void> stopPlayback() async => _player.stop();

  /// Seek to a position during playback.
  Future<void> seek(Duration position) async => _player.seek(position);

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_state);
    }
  }

  Future<void> close() async {
    await _amplitudeSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playingSub?.cancel();
    await _recorder.dispose();
    await _player.dispose();
    await _controller.close();
  }
}

/// State for voice message recording and playback.
class VoiceMessageState {
  final bool isRecording;
  final List<double> amplitudeLevels;
  final Duration recordingDuration;
  final Uint8List? recordedBytes;

  /// Playback state.
  final bool isPlaying;
  final Duration playbackPosition;
  final Duration? playbackDuration;

  const VoiceMessageState({
    this.isRecording = false,
    this.amplitudeLevels = const [],
    this.recordingDuration = Duration.zero,
    this.recordedBytes,
    this.isPlaying = false,
    this.playbackPosition = Duration.zero,
    this.playbackDuration,
  });

  VoiceMessageState copyWith({
    bool? isRecording,
    List<double>? amplitudeLevels,
    Duration? recordingDuration,
    Uint8List? recordedBytes,
    bool? isPlaying,
    Duration? playbackPosition,
    Duration? playbackDuration,
  }) =>
      VoiceMessageState(
        isRecording: isRecording ?? this.isRecording,
        amplitudeLevels: amplitudeLevels ?? this.amplitudeLevels,
        recordingDuration: recordingDuration ?? this.recordingDuration,
        recordedBytes: recordedBytes ?? this.recordedBytes,
        isPlaying: isPlaying ?? this.isPlaying,
        playbackPosition: playbackPosition ?? this.playbackPosition,
        playbackDuration: playbackDuration ?? this.playbackDuration,
      );
}
