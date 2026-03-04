import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'model_architecture.dart';
import 'model_loader.dart';

/// Create an [OnlineRecognizer] for the given ASR architecture.
///
/// [fileStructure] maps logical names (e.g. 'encoder', 'tokens') to paths
/// relative to the model root. [loader] resolves those paths to the file
/// system. [modelId] is passed to the loader for path resolution.
///
/// Throws [ArgumentError] for architectures not supported as online ASR.
Future<sherpa_onnx.OnlineRecognizer> buildAsrRecognizer(
  ModelArchitecture architecture,
  Map<String, String> fileStructure,
  ModelLoader loader,
  String modelId,
) async {
  final modelConfig = await _buildModelConfig(
    architecture,
    fileStructure,
    loader,
    modelId,
  );
  return sherpa_onnx.OnlineRecognizer(
    sherpa_onnx.OnlineRecognizerConfig(model: modelConfig, ruleFsts: ''),
  );
}

Future<sherpa_onnx.OnlineModelConfig> _buildModelConfig(
  ModelArchitecture architecture,
  Map<String, String> files,
  ModelLoader loader,
  String modelId,
) async {
  final tokens = await loader.loadModelFile(modelId, files['tokens']!);

  switch (architecture) {
    case ModelArchitecture.transducer:
      return sherpa_onnx.OnlineModelConfig(
        transducer: sherpa_onnx.OnlineTransducerModelConfig(
          encoder: await loader.loadModelFile(modelId, files['encoder']!),
          decoder: await loader.loadModelFile(modelId, files['decoder']!),
          joiner: await loader.loadModelFile(modelId, files['joiner']!),
        ),
        tokens: tokens,
        modelType: '',
        debug: false,
      );

    case ModelArchitecture.ctc:
      return sherpa_onnx.OnlineModelConfig(
        zipformer2Ctc: sherpa_onnx.OnlineZipformer2CtcModelConfig(
          model: await loader.loadModelFile(modelId, files['encoder']!),
        ),
        tokens: tokens,
        modelType: 'zipformer2_ctc',
        debug: false,
      );

    case ModelArchitecture.onlineNemoCtc:
      return sherpa_onnx.OnlineModelConfig(
        nemoCtc: sherpa_onnx.OnlineNemoCtcModelConfig(
          model: await loader.loadModelFile(modelId, files['model']!),
        ),
        tokens: tokens,
        modelType: 'nemo_ctc',
        debug: false,
      );

    default:
      throw ArgumentError(
        'Unsupported ASR architecture for online recognition: $architecture',
      );
  }
}
