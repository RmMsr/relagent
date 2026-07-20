import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/recording_provider.dart';
import '/providers/settings_provider.dart';
import '/voice/voice_service.dart';

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
    } else if (recordingState.recordingStatus == AudioRecordingStatus.paused) {
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
          color: theme.colorScheme.onSurfaceVariant,
          size: 32,
        );
        tooltip = 'Continuous listening disabled';
      }
    } else if (recordingState.isRecording) {
      icon = Icon(Icons.mic, color: theme.colorScheme.primary, size: 32);
      tooltip = 'Recording active';
    } else {
      icon = Icon(Icons.mic_none, color: theme.colorScheme.onSurfaceVariant, size: 32);
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

  final List<double> _targetHeights = List.filled(
    _amplitudeHistorySize,
    _minBarHeight,
  );
  final List<double> _currentHeights = List.filled(
    _amplitudeHistorySize,
    _minBarHeight,
  );

  @override
  void initState() {
    super.initState();

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

    for (int i = 0; i < _amplitudeHistorySize; i++) {
      _targetHeights[i] = i < heights.length ? heights[i] : _minBarHeight;
    }

    for (int i = 0; i < _amplitudeHistorySize; i++) {
      final targetHeight = _targetHeights[i];
      final currentHeight = _currentHeights[i];

      final isRising = targetHeight > currentHeight;
      final duration = isRising ? _riseDuration : _fallDuration;
      final curve = isRising ? _riseCurve : _fallCurve;

      _animationControllers[i].duration = duration;
      _heightAnimations[i] =
          Tween<double>(begin: currentHeight, end: targetHeight).animate(
            CurvedAnimation(parent: _animationControllers[i], curve: curve),
          );

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
      spacing: 2.0,
      children: List.generate(_amplitudeHistorySize, (index) {
        final level = _currentHeights[index];
        final barHeight = 24 * level;

        return Container(
          width: 6,
          height: 32,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 4,
            height: barHeight,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(1.0),
            ),
          ),
        );
      }),
    );
  }
}

/// Recording button widget that controls speech recognition.
class RecorderButton extends ConsumerWidget {
  const RecorderButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          return;
        }

        if (recordingState.isRecording) {
          ref.read(recordingProvider.notifier).stopDictation();
        } else {
          ref.read(recordingProvider.notifier).startDictation();
        }
      },
      icon: SizedBox(
        width: 48,
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (recordingState.isRecording &&
                recordingState.barHeights.isNotEmpty)
              VolumeBarVisualizer(barHeights: recordingState.barHeights),
            Opacity(
              opacity:
                  recordingState.isRecording &&
                      recordingState.barHeights.isNotEmpty
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
