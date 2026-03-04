import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sherpa_voice/tts_config.dart';

import '/config/app_config.dart';
import '/models/model_catalog.dart';
import '/utils/files.dart';
import '/utils/logger.dart';
import 'package:sherpa_voice/model_loader.dart';

/// Metadata needed to configure the TTS engine.
class TtsModelMetadata {
  final ModelArchitecture architecture;
  final Map<String, String> fileStructure;
  final ModelLoader loader;
  final String modelId;

  const TtsModelMetadata({
    required this.architecture,
    required this.fileStructure,
    required this.loader,
    required this.modelId,
  });
}

/// Pre-cache TTS model files from assets to allow background isolate access.
/// MUST be called from main isolate before spawning TTS worker.
/// Only needed for asset-based models.
Future<void> preCacheTtsModelFiles({String? modelName}) async {
  final name = modelName ?? AppConfig.ttsModelName;
  if (name == null) return;

  Logger.debug('[TTS] Pre-caching model files for $name...');
  final stopwatch = Stopwatch()..start();

  await copyAssetFileToCache('$name/model.onnx');
  await copyAssetFileToCache('$name/voices.bin');
  await copyAssetDirectoryToCache('$name/espeak-ng-data');
  await copyAssetFileToCache('$name/tokens.txt');

  stopwatch.stop();
  Logger.debug('[TTS] Model files cached (${stopwatch.elapsedMilliseconds}ms)');
}

/// Create an OfflineTts using explicit model metadata.
Future<sherpa_onnx.OfflineTts> createOfflineTtsFromMetadata(
  TtsModelMetadata metadata,
) async {
  Logger.debug('[TTS] Creating OfflineTts with ${metadata.architecture.name}');
  return buildTtsEngine(
    metadata.architecture,
    metadata.fileStructure,
    metadata.loader,
    metadata.modelId,
  );
}

/// Create an OfflineTts using a model bundled in assets (asset shortcut path).
/// Bundling a model in assets is a pre-download convenience — it ships the model
/// pre-installed so the user skips the first-run download. This path is not
/// deprecated; it runs alongside the downloaded-model path.
Future<sherpa_onnx.OfflineTts> createOfflineTts({String? modelName}) async {
  final modelConfig = await _getAssetOfflineTtsModelConfig(
    modelName: modelName,
  );

  Logger.debug('[TTS] Creating OfflineTts with config:');
  Logger.debug('  - Model: ${modelConfig.kokoro.model}');
  Logger.debug('  - Voices: ${modelConfig.kokoro.voices}');
  Logger.debug('  - DataDir: ${modelConfig.kokoro.dataDir}');
  Logger.debug('  - Tokens: ${modelConfig.kokoro.tokens}');

  final config = sherpa_onnx.OfflineTtsConfig(
    model: modelConfig,
    ruleFsts: '',
    maxNumSenetences: 1,
  );

  return sherpa_onnx.OfflineTts(config);
}

/// Asset shortcut: build config from a Kokoro model bundled in assets.
Future<sherpa_onnx.OfflineTtsModelConfig> _getAssetOfflineTtsModelConfig({
  String? modelName,
}) async {
  final name = modelName ?? AppConfig.ttsModelName!;

  final kokoroConfig = sherpa_onnx.OfflineTtsKokoroModelConfig(
    model: await copyAssetFileToCache('$name/model.onnx'),
    voices: await copyAssetFileToCache('$name/voices.bin'),
    dataDir: await copyAssetDirectoryToCache('$name/espeak-ng-data'),
    tokens: await copyAssetFileToCache('$name/tokens.txt'),
  );

  return sherpa_onnx.OfflineTtsModelConfig(
    kokoro: kokoroConfig,
    numThreads: 2,
    debug: false,
  );
}
