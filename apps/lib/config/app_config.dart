import 'dart:convert';

import 'package:flutter/services.dart';

class AppConfig {
  // Copy assets/config.template.json to assets/config.json

  // Optional: name of a streaming ASR model directory bundled under assets/.
  // Bundling a model is a shortcut that ships it pre-installed so the user
  // does not need to download it on first launch. Omit (null) to require
  // the user to download an ASR model via the in-app model manager.
  // Models available at: https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models
  static String? speechRecognitionStreamingAsrModelName;

  // Optional: name of a TTS model directory bundled under assets/.
  // Same trade-off as above — bundling is a convenience shortcut, not a
  // requirement. Omit (null) to require the user to download a TTS model.
  // Models available at: https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models
  static String? ttsModelName;

  static Future<void> load() async {
    final config = jsonDecode(
      await rootBundle.loadString('assets/config.json'),
    );

    speechRecognitionStreamingAsrModelName =
        config['speech_recognition']?['streaming_asr_model'];
    ttsModelName = config['tts']?['model'];
  }
}
