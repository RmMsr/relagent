/// Architecture/engine of the model, determines how to configure sherpa-onnx.
enum ModelArchitecture {
  /// Zipformer transducer: encoder + decoder + joiner
  transducer,

  /// CTC: encoder only (e.g., omnilingual model)
  ctc,

  /// Piper VITS: model.onnx + tokens.txt + espeak-ng-data
  vitsPiper,

  /// Kokoro: model.onnx + voices.bin + tokens.txt + espeak-ng-data
  kokoro,

  /// NeMo CTC streaming: model.onnx + tokens.txt
  onlineNemoCtc,

  /// NeMo offline transducer: encoder + decoder + joiner (VAD-simulated streaming)
  offlineNemoTransducer,

  /// Pocket TTS: lmFlow + lmMain + encoder + decoder + textConditioner + vocabJson + tokenScoresJson
  pocket,
}

/// Type of voice model.
enum ModelType { asr, tts }
