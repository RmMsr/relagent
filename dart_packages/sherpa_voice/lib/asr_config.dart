import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'model_architecture.dart';
import 'model_loader.dart';

/// Create an [OnlineRecognizer] for the given ASR architecture.
///
/// [fileStructure] maps logical names (e.g. 'encoder', 'tokens') to paths
/// relative to the model root. [loader] resolves those paths to the file
/// system. [modelId] is passed to the loader for path resolution.
///
/// Throws [ArgumentError] for architectures not supported as online ASR —
/// see [ModelArchitectureCapabilities.isOfflineAsr] and
/// [buildOfflineAsrRecognizer] for those instead.
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
          // Single-file CTC exports are keyed 'model', not 'encoder' — see
          // inspectDirectory in the voice-catalog evaluator: only filenames
          // that actually contain "encoder" get the 'encoder' key.
          model: await loader.loadModelFile(modelId, files['model']!),
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

/// Create an [OfflineRecognizer] for an offline-only ASR architecture (see
/// [ModelArchitectureCapabilities.isOfflineAsr]).
///
/// [language] forces recognition language for architectures that need one
/// (currently just Whisper — see the class doc on [ModelArchitecture.whisper]).
/// Throws [StateError] if such an architecture is given no language, since
/// letting sherpa-onnx auto-detect can silently lock onto the wrong language
/// on marginal audio.
Future<sherpa_onnx.OfflineRecognizer> buildOfflineAsrRecognizer(
  ModelArchitecture architecture,
  Map<String, String> fileStructure,
  ModelLoader loader,
  String modelId, {
  String? language,
}) async {
  final modelConfig = await _buildOfflineModelConfig(
    architecture,
    fileStructure,
    loader,
    modelId,
    language,
  );
  return sherpa_onnx.OfflineRecognizer(
    sherpa_onnx.OfflineRecognizerConfig(model: modelConfig),
  );
}

Future<sherpa_onnx.OfflineModelConfig> _buildOfflineModelConfig(
  ModelArchitecture architecture,
  Map<String, String> files,
  ModelLoader loader,
  String modelId,
  String? language,
) async {
  switch (architecture) {
    case ModelArchitecture.whisper:
      if (language == null || language.isEmpty) {
        throw StateError(
          'Whisper model "$modelId" has no forced language configured. '
          'Set at least one language on the model before using it for '
          'recognition — auto-detection is not supported.',
        );
      }
      return sherpa_onnx.OfflineModelConfig(
        whisper: sherpa_onnx.OfflineWhisperModelConfig(
          encoder: await loader.loadModelFile(modelId, files['encoder']!),
          decoder: await loader.loadModelFile(modelId, files['decoder']!),
          language: language,
          task: 'transcribe',
        ),
        tokens: await loader.loadModelFile(modelId, files['tokens']!),
        modelType: 'whisper',
        numThreads: 2,
        debug: false,
      );

    default:
      // offlineNemoTransducer and any other encoder+decoder+joiner offline
      // architecture routed here today.
      return sherpa_onnx.OfflineModelConfig(
        transducer: sherpa_onnx.OfflineTransducerModelConfig(
          encoder: await loader.loadModelFile(modelId, files['encoder']!),
          decoder: await loader.loadModelFile(modelId, files['decoder']!),
          joiner: await loader.loadModelFile(modelId, files['joiner']!),
        ),
        tokens: await loader.loadModelFile(modelId, files['tokens']!),
        modelType: 'nemo_transducer',
        numThreads: 2,
        debug: false,
      );
  }
}
