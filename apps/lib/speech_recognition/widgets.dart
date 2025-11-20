import 'package:flutter/material.dart';
import '/speech_recognition/services.dart';

enum RecordingState { idle, initializing, recording }

class RecorderButton extends StatefulWidget {
  final ValueChanged<String> onTextRecognized;
  final VoidCallback onTextFinished;

  const RecorderButton({
    super.key,
    required this.onTextRecognized,
    required this.onTextFinished,
  });

  @override
  RecorderButtonState createState() => RecorderButtonState();
}

class RecorderButtonState extends State<RecorderButton>
    with SingleTickerProviderStateMixin {
  RecordingState _state = RecordingState.idle;
  ASR? _asr;
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
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onRecordingStarted() {
    if (mounted) {
      setState(() {
        _state = RecordingState.recording;
      });
      _pulseController.repeat(reverse: true);
    }
  }

  void _startRecording() async {
    setState(() {
      _state = RecordingState.initializing;
    });

    if (_asr == null) {
      _asr = ASR(
        textRecognized: widget.onTextRecognized,
        textFinished: widget.onTextFinished,
        onRecordingStarted: _onRecordingStarted,
      );
      _asr!.init();
    }
    _asr!.start();
  }

  void _stopRecording() {
    _asr!.stop();
    _pulseController.stop();
    _pulseController.reset();
    setState(() {
      _state = RecordingState.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Widget icon;
    switch (_state) {
      case RecordingState.idle:
        icon = Icon(Icons.mic, color: theme.colorScheme.primary);
        break;
      case RecordingState.initializing:
        icon = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: theme.colorScheme.primary,
          ),
        );
        break;
      case RecordingState.recording:
        icon = AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: _pulseAnimation.value,
              child: Icon(
                Icons.stop_circle,
                color: Colors.red,
              ),
            );
          },
        );
        break;
    }

    return IconButton(
      onPressed: _state == RecordingState.initializing
          ? null
          : () {
              _state == RecordingState.recording
                  ? _stopRecording()
                  : _startRecording();
            },
      icon: icon,
    );
  }
}
