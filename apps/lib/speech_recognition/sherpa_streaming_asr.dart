import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sherpa_voice/asr_config.dart';

import '/config/app_config.dart';
import '/utils/files.dart';
import 'asr_metadata.dart';

/// Create an OnlineRecognizer using explicit model metadata.
Future<sherpa_onnx.OnlineRecognizer> createOnlineRecognizerFromMetadata(
  AsrModelMetadata metadata,
) async {
  return buildAsrRecognizer(
    metadata.architecture,
    metadata.fileStructure,
    metadata.loader,
    metadata.modelId,
  );
}

/// Create an OnlineRecognizer using a model bundled in assets (asset shortcut path).
/// Bundling a model is a pre-download convenience — not a deprecated pattern.
Future<sherpa_onnx.OnlineRecognizer> createOnlineRecognizer() async {
  final modelDir = AppConfig.speechRecognitionStreamingAsrModelName!;
  final config = sherpa_onnx.OnlineRecognizerConfig(
    model: sherpa_onnx.OnlineModelConfig(
      transducer: sherpa_onnx.OnlineTransducerModelConfig(
        encoder: await copyAssetFileToCache('$modelDir/encoder.onnx'),
        decoder: await copyAssetFileToCache('$modelDir/decoder.onnx'),
        joiner: await copyAssetFileToCache('$modelDir/joiner.onnx'),
      ),
      tokens: await copyAssetFileToCache('$modelDir/tokens.txt'),
      modelType: 'zipformer2',
    ),
    ruleFsts: '',
  );
  return sherpa_onnx.OnlineRecognizer(config);
}
