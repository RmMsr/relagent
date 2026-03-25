import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sherpa_voice/tts_config.dart';

import '/models/model_catalog.dart';
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
