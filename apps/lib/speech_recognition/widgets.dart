import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '/models/settings.dart';
import '/providers/recording_provider.dart';
import '/providers/settings_provider.dart';

class RecordingStateIndicator extends StatelessWidget {
  final RecordingState recordingState;
  final VoiceMode voiceMode;

  const RecordingStateIndicator({
    super.key,
    required this.recordingState,
    required this.voiceMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget icon;
    String tooltip;

    if (recordingState.error != null) {
      icon = Icon(
        Icons.error_outline,
        color: theme.colorScheme.error,
        size: 32,
      );
      tooltip = 'Recording error: ${recordingState.error}';
    } else if (recordingState.isInitializing) {
      icon = SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
        ),
      );
      tooltip = 'Initializing speech recognition...';
    } else if (recordingState.recordState == RecordState.pause) {
      icon = Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.orange, width: 2),
        ),
        child: Icon(Icons.pause, color: Colors.orange, size: 20),
      );
      tooltip = 'Recording paused - audio interrupted';
    } else if (voiceMode == VoiceMode.listening ||
        voiceMode == VoiceMode.conversation) {
      if (recordingState.isRecording) {
        icon = Icon(
          Icons.radio_button_checked,
          color: theme.colorScheme.primary,
          size: 32,
        );
        tooltip = 'Listening continuously';
      } else {
        icon = Icon(
          Icons.mic_none,
          color: theme.colorScheme.onSurface,
          size: 32,
        );
        tooltip = 'Continuous listening disabled';
      }
    } else if (recordingState.isRecording) {
      icon = Icon(Icons.mic, color: theme.colorScheme.primary, size: 32);
      tooltip = 'Recording active';
    } else {
      icon = Icon(Icons.mic_none, color: theme.colorScheme.onSurface, size: 32);
      tooltip = 'Ready to record';
    }

    return Tooltip(
      message: tooltip,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: SizedBox(
          key: ValueKey(tooltip),
          width: 48,
          height: 32,
          child: Center(child: icon),
        ),
      ),
    );
  }
}

class VolumeBarVisualizer extends StatefulWidget {
  final List<double> barHeights;

  const VolumeBarVisualizer({super.key, required this.barHeights});

  @override
  State<VolumeBarVisualizer> createState() => _VolumeBarVisualizerState();
}

class _VolumeBarVisualizerState extends State<VolumeBarVisualizer>
    with TickerProviderStateMixin {
  static const int _amplitudeHistorySize = 5;
  static const double _minBarHeight = 0.1;

  // VU-meter animation constants
  static const Duration _riseDuration = Duration(milliseconds: 50);
  static const Duration _fallDuration = Duration(milliseconds: 800);
  static const Curve _riseCurve = Curves.easeOut;
  static const Curve _fallCurve = Curves.easeOutCirc;

  late final List<AnimationController> _animationControllers;
  late final List<Animation<double>> _heightAnimations;

  // Current target heights for each bar
  final List<double> _targetHeights = List.filled(
    _amplitudeHistorySize,
    _minBarHeight,
  );
  // Current displayed heights (animated)
  final List<double> _currentHeights = List.filled(
    _amplitudeHistorySize,
    _minBarHeight,
  );

  @override
  void initState() {
    super.initState();

    // Initialize animation controllers for each bar
    _animationControllers = List.generate(
      _amplitudeHistorySize,
      (index) => AnimationController(duration: _fallDuration, vsync: this),
    );

    _heightAnimations = _animationControllers
        .map(
          (controller) => Tween<double>(
            begin: _minBarHeight,
            end: _minBarHeight,
          ).animate(CurvedAnimation(parent: controller, curve: _fallCurve)),
        )
        .toList();

    // Start listening to animations for 60fps updates
    for (int i = 0; i < _heightAnimations.length; i++) {
      _heightAnimations[i].addListener(() {
        if (mounted) {
          setState(() {
            _currentHeights[i] = _heightAnimations[i].value;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _animationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(VolumeBarVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.barHeights.isEmpty) {
      _resetBars();
      return;
    }

    if (widget.barHeights != oldWidget.barHeights) {
      _updateBarHeights();
    }
  }

  void _resetBars() {
    for (int i = 0; i < _animationControllers.length; i++) {
      _animationControllers[i].stop();
      _targetHeights[i] = _minBarHeight;
      _currentHeights[i] = _minBarHeight;
    }
    if (mounted) setState(() {});
  }

  void _updateBarHeights() {
    final heights = widget.barHeights;
    if (heights.isEmpty) return;

    // Direct update with pre-calculated heights from provider
    for (int i = 0; i < _amplitudeHistorySize; i++) {
      _targetHeights[i] = i < heights.length ? heights[i] : _minBarHeight;
    }

    // Animate each bar to its new target height
    for (int i = 0; i < _amplitudeHistorySize; i++) {
      final targetHeight = _targetHeights[i];
      final currentHeight = _currentHeights[i];

      // Choose animation based on rise/fall
      final isRising = targetHeight > currentHeight;
      final duration = isRising ? _riseDuration : _fallDuration;
      final curve = isRising ? _riseCurve : _fallCurve;

      // Update animation
      _animationControllers[i].duration = duration;
      _heightAnimations[i] =
          Tween<double>(begin: currentHeight, end: targetHeight).animate(
            CurvedAnimation(parent: _animationControllers[i], curve: curve),
          );

      // Restart animation
      _animationControllers[i].reset();
      _animationControllers[i].forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = theme.colorScheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2.0, // Tighter spacing for smaller bars
      children: List.generate(_amplitudeHistorySize, (index) {
        final level = _currentHeights[index];
        final barHeight = 24 * level; // Smaller bar height

        return Container(
          width: 6, // Smaller bar container width
          height: 32, // Smaller container height
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 4, // Smaller bar width
            height: barHeight,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(1.0), // Normal radius
            ),
          ),
        );
      }),
    );
  }
}

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

class RecorderButtonState extends ConsumerState<RecorderButton> {
  @override
  Widget build(BuildContext context) {
    final voiceMode = ref.watch(settingsProvider).voiceMode;
    final recordingState = ref.watch(recordingProvider);

    String tooltip;
    if (voiceMode == VoiceMode.listening ||
        voiceMode == VoiceMode.conversation) {
      tooltip = 'Stop listening';
    } else if (recordingState.isRecording) {
      tooltip = 'Stop recording';
    } else {
      tooltip = 'Start recording';
    }

    // Listen for text updates
    ref.listen<RecordingState>(recordingProvider, (previous, next) {
      if (previous?.recognizedText != next.recognizedText) {
        widget.onTextRecognized(next.recognizedText);
      }
      if (next.textToSubmit != null &&
          previous?.textToSubmit != next.textToSubmit) {
        debugPrint('RecorderButton: textToSubmit: "${next.textToSubmit}"');
        widget.onTextRecognized(next.textToSubmit!);
        widget.onTextFinished();
        ref.read(recordingProvider.notifier).clearTextToSubmit();
      }
    });

    return IconButton(
      onPressed: () {
        final voiceMode = ref.read(settingsProvider).voiceMode;
        final recordingState = ref.read(recordingProvider);

        if (voiceMode == VoiceMode.listening ||
            voiceMode == VoiceMode.conversation) {
          final newMode = voiceMode == VoiceMode.listening
              ? VoiceMode.silent
              : VoiceMode.reading;
          ref.read(settingsProvider.notifier).updateVoiceMode(newMode);
        } else {
          if (recordingState.isRecording) {
            ref.read(recordingProvider.notifier).stopOneShot();
          } else {
            ref.read(recordingProvider.notifier).startOneShot();
          }
        }
      },
      icon: SizedBox(
        width: 48, // Compact production size
        height: 32, // Compact production size
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (recordingState.recordState == RecordState.record)
              VolumeBarVisualizer(barHeights: recordingState.barHeights),
            Opacity(
              opacity: recordingState.recordState == RecordState.record
                  ? 0.3
                  : 1.0,
              child: RecordingStateIndicator(
                recordingState: recordingState,
                voiceMode: voiceMode,
              ),
            ),
          ],
        ),
      ),
      tooltip: tooltip,
    );
  }
}
