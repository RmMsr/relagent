import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/config/app_config.dart';
import '/utils/files.dart';

Future<sherpa_onnx.OnlineRecognizer> createOnlineRecognizer() async {
  final modelConfig = await getOnlineModelConfig();
  final config = sherpa_onnx.OnlineRecognizerConfig(
    model: modelConfig,
    ruleFsts: '',
  );

  return sherpa_onnx.OnlineRecognizer(config);
}

Future<sherpa_onnx.OnlineModelConfig> getOnlineModelConfig() async {
  final modelDir = AppConfig.speechRecognitionStreamingAsrModelName;
  // Inference models need to be accessible on the file system
  return sherpa_onnx.OnlineModelConfig(
    transducer: sherpa_onnx.OnlineTransducerModelConfig(
      encoder: await copyAssetFileToCache('$modelDir/encoder.onnx'),
      decoder: await copyAssetFileToCache('$modelDir/decoder.onnx'),
      joiner: await copyAssetFileToCache('$modelDir/joiner.onnx'),
    ),
    tokens: await copyAssetFileToCache('$modelDir/tokens.txt'),
    modelType: 'zipformer2',
  );
}
