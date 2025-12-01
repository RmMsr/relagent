import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/config/app_config.dart';
import '/utils/files.dart';

/// Pre-cache TTS model files to allow background isolate access
/// MUST be called from main isolate before spawning TTS worker
Future<void> preCacheTtsModelFiles({String? modelName}) async {
  final name = modelName ?? AppConfig.ttsModelName;
  debugPrint('[TTS] Pre-caching model files for $name...');

  final stopwatch = Stopwatch()..start();

  // Copy all required files to cache in main isolate
  // This ensures background isolates can access them without rootBundle
  await copyAssetFileToCache('$name/model.onnx');
  await copyAssetFileToCache('$name/voices.bin');
  await copyAssetDirectoryToCache('$name/espeak-ng-data');
  await copyAssetFileToCache('$name/tokens.txt');

  stopwatch.stop();
  debugPrint('[TTS] ✓ Model files cached (${stopwatch.elapsedMilliseconds}ms)');
}

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
    numThreads: 2, // Use 2 threads for better performance on multi-core devices
    debug: false,
  );
}
