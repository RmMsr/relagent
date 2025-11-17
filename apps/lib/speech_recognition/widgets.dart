import 'package:flutter/material.dart';
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

class RecorderButtonState extends State<RecorderButton> {
  bool _isRecording = false;
  ASR? _asr;

  void _startRecording() async {
    if (_asr == null) {
      _asr = ASR(
        textRecognized: widget.onTextRecognized,
        textFinished: widget.onTextFinished,
      );
      _asr!.init();
    }
    _asr!.start();

    setState(() {
      _isRecording = true;
    });
  }

  void _stopRecording() {
    _asr!.stop();
    setState(() {
      _isRecording = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    var micStart = Icon(Icons.mic, color: theme.colorScheme.primary);
    const micStop = Icon(Icons.square, color: Colors.red);

    return IconButton(
      onPressed: () {
        _isRecording ? _stopRecording() : _startRecording();
      },
      icon: _isRecording ? micStop : micStart,
    );
  }
}
