import 'dart:convert';

import 'package:flutter/services.dart';

class AppConfig {
  // Copy assets/config.template.json to assets/config.json

  // Ensure there is a directory with a streaming asr model with that name under /assets
  // Download it from: https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models
  static late final String speechRecognitionStreamingAsrModelName;

  // Ensure there is a directory with a TTS model with that name under /assets
  // Download it from: https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models
  static late final String ttsModelName;

  static Future<void> load() async {
    final config = jsonDecode(
      await rootBundle.loadString('assets/config.json'),
    );

    speechRecognitionStreamingAsrModelName =
        config['speech_recognition']['streaming_asr_model'];
    ttsModelName = config['tts']['model'];
  }
}
