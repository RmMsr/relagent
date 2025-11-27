import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/config/app_config.dart';
import '/utils/files.dart';

Future<sherpa_onnx.OfflineTts> createOfflineTts({String? modelName}) async {
  final modelConfig = await getOfflineTtsModelConfig(modelName: modelName);
  final config = sherpa_onnx.OfflineTtsConfig(
    model: modelConfig,
    ruleFsts: '',
    maxNumSenetences: 1,
  );

  return sherpa_onnx.OfflineTts(config);
}

Future<sherpa_onnx.OfflineTtsModelConfig> getOfflineTtsModelConfig({
  String? modelName,
}) async {
  final name = modelName ?? AppConfig.ttsModelName;

  // Kokoro model configuration
  // Model files need to be accessible on the file system
  final kokoroConfig = sherpa_onnx.OfflineTtsKokoroModelConfig(
    model: await copyAssetFileToCache('$name/model.onnx'),
    voices: await copyAssetFileToCache('$name/voices.bin'),
    dataDir: await copyAssetDirectoryToCache('$name/espeak-ng-data'),
    tokens: await copyAssetFileToCache('$name/tokens.txt'),
  );

  return sherpa_onnx.OfflineTtsModelConfig(
    kokoro: kokoroConfig,
    numThreads: 1,
    debug: false,
  );
}
