import 'dart:convert';

import 'package:flutter/services.dart';

class AppConfig {
  // Copy assets/config.template.json to assets/config.json

  // Ensure there is a directory with a streaming asr model with that name under /assets
  // Download it from: https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models
  static late final String speechRecognitionStreamingAsrModelName;

  // URL to an legacy OpenAI compatible API endpoint
  static late final String simpleChatBaseUrl;

  // Model name that is usable with the simple chat API endpoint
  static late final String simpleChatModel;

  static load() async {
    final config = jsonDecode(
      await rootBundle.loadString('assets/config.json'),
    );

    speechRecognitionStreamingAsrModelName =
        config['speech_recognition']['streaming_asr_model'];
    simpleChatBaseUrl = config['simple_chat']['base_url'];
    simpleChatModel = config['simple_chat']['model'];
  }
}
