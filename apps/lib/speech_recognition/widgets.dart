import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '/speech_recognition/services.dart';

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
  RecordState _recordState = RecordState.stop;
  bool _isInitializing = false;
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
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _asr?.dispose();
    super.dispose();
  }

  void _onRecordStateChanged(RecordState state) {
    if (mounted) {
      setState(() {
        _recordState = state;
        _isInitializing = false;
      });

      if (state == RecordState.record) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  void _startRecording() async {
    setState(() {
      _isInitializing = true;
    });

    if (_asr == null) {
      _asr = ASR(
        textRecognized: widget.onTextRecognized,
        textFinished: widget.onTextFinished,
        onRecordStateChanged: _onRecordStateChanged,
      );
      _asr!.init();
    }
    _asr!.start();
  }

  void _stopRecording() {
    _asr!.stop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Widget icon;
    if (_isInitializing) {
      // Show loading spinner while initializing
      icon = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: theme.colorScheme.primary,
        ),
      );
    } else if (_recordState == RecordState.record) {
      // Show pulsing stop button while recording
      icon = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _pulseAnimation.value,
            child: Icon(Icons.stop_circle, color: Colors.red),
          );
        },
      );
    } else {
      // Show mic icon when idle
      icon = Icon(Icons.mic, color: theme.colorScheme.primary);
    }

    return IconButton(
      onPressed: _isInitializing
          ? null
          : () {
              _recordState == RecordState.record
                  ? _stopRecording()
                  : _startRecording();
            },
      icon: icon,
    );
  }
}
