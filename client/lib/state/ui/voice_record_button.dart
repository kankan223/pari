import 'package:flutter/material.dart';

import '../domain/voice_message_bloc.dart';
import '../domain/voice_message_state.dart';

/// A microphone button that toggles voice recording.
///
/// Long-press to start recording, release to stop and send.
/// Shows a recording indicator with amplitude levels while recording.
///
/// SECURITY CHECKPOINT: the button only triggers the recorder port —
/// voice bytes are encrypted before they leave the device.
class VoiceRecordButton extends StatefulWidget {
  final VoiceMessageBloc voiceBloc;
  final void Function(List<int> audioBytes) onRecorded;

  const VoiceRecordButton({
    super.key,
    required this.voiceBloc,
    required this.onRecorded,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VoiceMessageState>(
      stream: widget.voiceBloc.state,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final isRecording = state?.isRecording ?? false;

        if (isRecording) {
          return _buildRecordingIndicator(state);
        }

        return GestureDetector(
          onLongPressStart: (_) => widget.voiceBloc.startRecording(),
          onLongPressEnd: (_) => _stopAndSend(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic_rounded,
              color: Colors.grey[600],
              size: 22,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordingIndicator(VoiceMessageState? state) {
    final levels = state?.amplitudeLevels ?? [];
    final lastLevel = levels.isNotEmpty ? levels.last : 0.0;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + (_pulseController.value * 0.15);
        return Transform.scale(
          scale: scale,
          child: GestureDetector(
            onTap: () => _stopAndSend(),
            onLongPressCancel: () => _cancelRecording(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1 + lastLevel * 0.3),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red, width: 2),
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.red,
                size: 22,
              ),
            ),
          ),
        );
      },
    );
  }

  void _stopAndSend() async {
    final bytes = await widget.voiceBloc.stopRecording();
    if (bytes != null && bytes.isNotEmpty) {
      widget.onRecorded(bytes);
    }
  }

  void _cancelRecording() async {
    await widget.voiceBloc.cancelRecording();
  }
}
