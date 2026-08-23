import 'dart:math';

import 'package:flutter/material.dart';

import '../../repository/domain/voice_message.dart';
import '../domain/voice_message_bloc.dart';
import '../domain/voice_message_state.dart';
import 'vault_theme.dart';

/// A voice message bubble in the chat thread.
///
/// Displays a play/pause button, waveform visualization, and duration.
/// Consumes [VoiceMessageBloc] state for playback position and controls.
///
/// SECURITY CHECKPOINT: voice bytes are encrypted — the bubble renders
/// only the duration and waveform, never raw audio data.
class VoiceMessageBubble extends StatefulWidget {
  final VoiceMessage message;
  final VoiceMessageBloc voiceBloc;
  final bool isSent;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.voiceBloc,
    required this.isSent,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final bubbleColor = widget.isSent ? VaultTheme.vaultBlue : Colors.white;
    final iconColor = widget.isSent ? Colors.white : VaultTheme.vaultBlue;

    return StreamBuilder<VoiceMessageState>(
      stream: widget.voiceBloc.state,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final isPlaying = state?.isPlaying ?? false;
        final position = state?.playbackPosition ?? Duration.zero;
        final duration = Duration(milliseconds: msg.durationMs);
        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        return Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Play/Pause button.
                  GestureDetector(
                    onTap: () {
                      if (isPlaying) {
                        widget.voiceBloc.pausePlayback();
                      } else {
                        widget.voiceBloc.playMessage(msg);
                      }
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: widget.isSent
                            ? Colors.white.withValues(alpha: 0.2)
                            : VaultTheme.vaultBlue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: iconColor,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Waveform visualization.
                  Expanded(
                    child: _Waveform(
                      levels: state?.amplitudeLevels ?? _fakeWaveform(40),
                      progress: progress.clamp(0.0, 1.0),
                      color: iconColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Duration text.
              Text(
                _formatDuration(isPlaying ? position : duration),
                style: TextStyle(
                  color: widget.isSent ? Colors.white54 : Colors.black38,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Generate fake waveform levels for display when no recording data.
  static List<double> _fakeWaveform(int count) {
    final rng = Random(42);
    return List.generate(count, (_) => rng.nextDouble() * 0.6 + 0.1);
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Simple waveform visualization bar.
class _Waveform extends StatelessWidget {
  final List<double> levels;
  final double progress;
  final Color color;

  const _Waveform({
    required this.levels,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) {
      return const SizedBox(height: 24);
    }
    return SizedBox(
      height: 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(levels.length, (i) {
          final fraction = i / levels.length;
          final isPlayed = fraction <= progress;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Container(
                height: max(2, levels[i] * 24),
                decoration: BoxDecoration(
                  color: isPlayed
                      ? color
                      : color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
