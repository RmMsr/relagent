import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/recording_provider.dart';
import '/providers/settings_provider.dart';

class RecorderButton extends ConsumerStatefulWidget {
  final ValueChanged<String> onTextRecognized;
  final VoidCallback onTextFinished;

  const RecorderButton({
    super.key,
    required this.onTextRecognized,
    required this.onTextFinished,
  });

  @override
  ConsumerState<RecorderButton> createState() => RecorderButtonState();
}

class RecorderButtonState extends ConsumerState<RecorderButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleButtonPress() {
    final voiceMode = ref.read(settingsProvider).voiceMode;
    final recordingState = ref.read(recordingProvider);

    if (voiceMode == VoiceMode.listening ||
        voiceMode == VoiceMode.conversation) {
      // In continuous modes: button toggles mode OFF
      final newMode = voiceMode == VoiceMode.listening
          ? VoiceMode.silent
          : VoiceMode.reading;
      ref.read(settingsProvider.notifier).updateVoiceMode(newMode);
    } else {
      // In one-shot modes: button starts/stops recording
      if (recordingState.isRecording) {
        ref.read(recordingProvider.notifier).stopOneShot();
      } else {
        ref.read(recordingProvider.notifier).startOneShot();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final voiceMode = ref.watch(settingsProvider).voiceMode;
    final recordingState = ref.watch(recordingProvider);

    // Update text in parent when recognized text changes
    ref.listen<RecordingState>(recordingProvider, (previous, next) {
      // Update text field with recognized text
      if (previous?.recognizedText != next.recognizedText) {
        widget.onTextRecognized(next.recognizedText);
      }

      // In continuous modes, when textToSubmit appears, submit it
      if (next.textToSubmit != null &&
          previous?.textToSubmit != next.textToSubmit) {
        // Update text field one more time to show what's being submitted
        widget.onTextRecognized(next.textToSubmit!);
        // Submit the text
        widget.onTextFinished();
        // Clear the textToSubmit flag
        ref.read(recordingProvider.notifier).clearTextToSubmit();
      }
    });

    // Start/stop pulse animation based on recording state
    if (recordingState.isRecording) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }

    // Determine icon based on what action will happen when button is pressed
    Widget icon;
    String tooltip;

    if (voiceMode == VoiceMode.listening ||
        voiceMode == VoiceMode.conversation) {
      // In continuous modes: button will toggle mode OFF
      // Show "mic off" to indicate it will stop listening
      icon = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _pulseAnimation.value,
            child: Icon(Icons.mic_off, color: theme.colorScheme.primary),
          );
        },
      );
      tooltip = 'Stop listening';
    } else if (recordingState.isRecording) {
      // Currently recording in single mode: button will stop
      // Show stop icon
      icon = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _pulseAnimation.value,
            child: Icon(Icons.stop_circle, color: Colors.red),
          );
        },
      );
      tooltip = 'Stop recording';
    } else {
      // Idle in single mode: button will start recording
      // Show mic icon to indicate it will start
      icon = Icon(Icons.mic, color: theme.colorScheme.primary);
      tooltip = 'Start recording';
    }

    return IconButton(
      onPressed: _handleButtonPress,
      icon: icon,
      tooltip: tooltip,
    );
  }
}
