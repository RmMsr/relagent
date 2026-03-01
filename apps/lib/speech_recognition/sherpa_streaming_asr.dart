import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/config/app_config.dart';
import '/models/model_catalog.dart';
import '/utils/files.dart';
import '/voice/model_loader.dart';

/// Metadata needed to configure the ASR recognizer.
class AsrModelMetadata {
  final ModelArchitecture architecture;
  final Map<String, String> fileStructure;
  final ModelLoader loader;
  final String modelId;

  const AsrModelMetadata({
    required this.architecture,
    required this.fileStructure,
    required this.loader,
    required this.modelId,
  });
}

/// Create an OnlineRecognizer using explicit model metadata.
Future<sherpa_onnx.OnlineRecognizer> createOnlineRecognizerFromMetadata(
  AsrModelMetadata metadata,
) async {
  final modelConfig = await _buildModelConfig(metadata);
  final config = sherpa_onnx.OnlineRecognizerConfig(
    model: modelConfig,
    ruleFsts: '',
  );
  return sherpa_onnx.OnlineRecognizer(config);
}

/// Create an OnlineRecognizer using a model bundled in assets (asset shortcut path).
/// Bundling a model is a pre-download convenience — not a deprecated pattern.
Future<sherpa_onnx.OnlineRecognizer> createOnlineRecognizer() async {
  final modelConfig = await _getAssetOnlineModelConfig();
  final config = sherpa_onnx.OnlineRecognizerConfig(
    model: modelConfig,
    ruleFsts: '',
  );
  return sherpa_onnx.OnlineRecognizer(config);
}

Future<sherpa_onnx.OnlineModelConfig> _buildModelConfig(
  AsrModelMetadata metadata,
) async {
  final files = metadata.fileStructure;
  final loader = metadata.loader;
  final modelId = metadata.modelId;

  final tokens = await loader.loadModelFile(modelId, files['tokens']!);

  switch (metadata.architecture) {
    case ModelArchitecture.transducer:
      return sherpa_onnx.OnlineModelConfig(
        transducer: sherpa_onnx.OnlineTransducerModelConfig(
          encoder: await loader.loadModelFile(modelId, files['encoder']!),
          decoder: await loader.loadModelFile(modelId, files['decoder']!),
          joiner: await loader.loadModelFile(modelId, files['joiner']!),
        ),
        tokens: tokens,
        modelType: 'zipformer2',
      );

    case ModelArchitecture.ctc:
      return sherpa_onnx.OnlineModelConfig(
        zipformer2Ctc: sherpa_onnx.OnlineZipformer2CtcModelConfig(
          model: await loader.loadModelFile(modelId, files['encoder']!),
        ),
        tokens: tokens,
        modelType: 'zipformer2_ctc',
      );

    case ModelArchitecture.onlineNemoCtc:
      return sherpa_onnx.OnlineModelConfig(
        nemoCtc: sherpa_onnx.OnlineNemoCtcModelConfig(
          model: await loader.loadModelFile(modelId, files['model']!),
        ),
        tokens: tokens,
        modelType: 'nemo_ctc',
      );

    default:
      throw ArgumentError(
        'Unsupported ASR architecture: ${metadata.architecture}',
      );
  }
}

/// Asset shortcut: build config from a transducer model bundled in assets.
Future<sherpa_onnx.OnlineModelConfig> _getAssetOnlineModelConfig() async {
  final modelDir = AppConfig.speechRecognitionStreamingAsrModelName!;
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
