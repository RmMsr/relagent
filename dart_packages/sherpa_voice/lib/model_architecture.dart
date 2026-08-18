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

  /// Whisper: encoder + decoder (no joiner) + tokens, as produced by
  /// sherpa-onnx's scripts/whisper/export-onnx.py, which names all three
  /// files with a shared "{model-name}-" prefix (e.g. "nb-whisper-base-
  /// encoder.onnx", "nb-whisper-base-tokens.txt") rather than the bare
  /// "encoder.onnx"/"tokens.txt" every other architecture here uses.
  /// Offline only — 30-second decode window, no streaming/partial results.
  whisper,
}

/// Type of voice model.
enum ModelType { asr, tts }

extension ModelArchitectureCapabilities on ModelArchitecture {
  /// Whether this architecture only has an offline (non-streaming) sherpa-onnx
  /// recognizer — needs [OfflineRecognizer] fed VAD-chunked segments (see
  /// buildOfflineAsrRecognizer in asr_config.dart) rather than the live
  /// [OnlineRecognizer] path (buildAsrRecognizer). Single source of truth for
  /// this split — production ASR backend selection and the voice-catalog
  /// evaluator both key off this.
  bool get isOfflineAsr =>
      this == ModelArchitecture.whisper ||
      this == ModelArchitecture.offlineNemoTransducer;
}
