import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'model_architecture.dart';
import 'model_loader.dart';

/// Create an [OfflineTts] engine for the given TTS architecture.
///
/// [fileStructure] maps logical names (e.g. 'model', 'voices', 'tokens',
/// 'dataDir') to paths relative to the model root. [loader] resolves those
/// paths to the file system. [modelId] is passed to the loader.
///
/// Throws [ArgumentError] for architectures not supported as TTS.
Future<sherpa_onnx.OfflineTts> buildTtsEngine(
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
  return sherpa_onnx.OfflineTts(
    sherpa_onnx.OfflineTtsConfig(
      model: modelConfig,
      ruleFsts: '',
      maxNumSenetences: 1,
    ),
  );
}

Future<sherpa_onnx.OfflineTtsModelConfig> _buildModelConfig(
  ModelArchitecture architecture,
  Map<String, String> files,
  ModelLoader loader,
  String modelId,
) async {
  switch (architecture) {
    case ModelArchitecture.kokoro:
      return sherpa_onnx.OfflineTtsModelConfig(
        kokoro: sherpa_onnx.OfflineTtsKokoroModelConfig(
          model: await loader.loadModelFile(modelId, files['model']!),
          voices: await loader.loadModelFile(modelId, files['voices']!),
          tokens: await loader.loadModelFile(modelId, files['tokens']!),
          dataDir: await loader.loadModelDirectory(modelId, files['dataDir']!),
          // Multilingual Kokoro v1.0+ requires a lexicon file.
          lexicon: files['lexicon'] != null
              ? await loader.loadModelFile(modelId, files['lexicon']!)
              : '',
        ),
        numThreads: 2,
        debug: false,
      );

    case ModelArchitecture.vitsPiper:
      return sherpa_onnx.OfflineTtsModelConfig(
        vits: sherpa_onnx.OfflineTtsVitsModelConfig(
          model: await loader.loadModelFile(modelId, files['model']!),
          tokens: await loader.loadModelFile(modelId, files['tokens']!),
          dataDir: await loader.loadModelDirectory(modelId, files['dataDir']!),
        ),
        numThreads: 2,
        debug: false,
      );

    case ModelArchitecture.pocket:
      return sherpa_onnx.OfflineTtsModelConfig(
        pocket: sherpa_onnx.OfflineTtsPocketModelConfig(
          lmFlow: await loader.loadModelFile(modelId, files['lmFlow']!),
          lmMain: await loader.loadModelFile(modelId, files['lmMain']!),
          encoder: await loader.loadModelFile(modelId, files['encoder']!),
          decoder: await loader.loadModelFile(modelId, files['decoder']!),
          textConditioner: await loader.loadModelFile(
            modelId,
            files['textConditioner']!,
          ),
          vocabJson: await loader.loadModelFile(modelId, files['vocabJson']!),
          tokenScoresJson: await loader.loadModelFile(
            modelId,
            files['tokenScoresJson']!,
          ),
        ),
        numThreads: 2,
        debug: false,
      );

    default:
      throw ArgumentError('Unsupported TTS architecture: $architecture');
  }
}
