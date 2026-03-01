import '/models/model_catalog.dart';
import '/models/settings.dart';
import '/providers/model_download_provider.dart';
import '/speech_recognition/sherpa_streaming_asr.dart';
import '/voice/download_model_loader.dart';

/// Resolved TTS model with absolute file paths (safe for isolate transfer).
class ResolvedTtsModel {
  final String modelId;
  final ModelArchitecture architecture;

  /// Absolute file paths keyed by logical name (e.g., 'model', 'tokens').
  final Map<String, String> resolvedPaths;

  const ResolvedTtsModel({
    required this.modelId,
    required this.architecture,
    required this.resolvedPaths,
  });
}

/// Resolve the selected ASR model to metadata, or null to use bundled.
Future<AsrModelMetadata?> resolveAsrMetadata(
  Settings settings,
  ModelDownloadState downloadState,
) async {
  final modelId = settings.selectedAsrModelId;
  if (modelId == null) return null;

  final entry = ModelCatalog.findById(modelId);
  if (entry == null) return null;
  if (entry.type != ModelType.asr) return null;
  if (!downloadState.isDownloaded(modelId)) return null;

  final loader = DownloadModelLoader(entry);
  return AsrModelMetadata(
    architecture: entry.architecture,
    fileStructure: entry.fileStructure,
    loader: loader,
    modelId: entry.id,
  );
}

/// Resolve the selected TTS model to a ResolvedTtsModel with absolute paths,
/// or null to use bundled. Resolves all paths in the main isolate.
Future<ResolvedTtsModel?> resolveTtsModel(
  Settings settings,
  ModelDownloadState downloadState,
) async {
  final modelId = settings.selectedTtsModelId;
  if (modelId == null) return null;

  final entry = ModelCatalog.findById(modelId);
  if (entry == null) return null;
  if (entry.type != ModelType.tts) return null;
  if (!downloadState.isDownloaded(modelId)) return null;

  final loader = DownloadModelLoader(entry);
  final resolvedPaths = <String, String>{};

  for (final logicalName in entry.fileStructure.keys) {
    final relativePath = entry.fileStructure[logicalName]!;
    if (logicalName == 'dataDir') {
      resolvedPaths[logicalName] = await loader.loadModelDirectory(
        entry.id,
        relativePath,
      );
    } else {
      resolvedPaths[logicalName] = await loader.loadModelFile(
        entry.id,
        relativePath,
      );
    }
  }

  return ResolvedTtsModel(
    modelId: entry.id,
    architecture: entry.architecture,
    resolvedPaths: resolvedPaths,
  );
}

/// Get the speaker count for the currently selected TTS model.
/// Returns the bundled Kokoro speaker count if no model is selected.
int getSelectedTtsSpeakerCount(Settings settings) {
  final modelId = settings.selectedTtsModelId;
  if (modelId == null) {
    // Bundled model is Kokoro with 54 speakers
    return 54;
  }

  final entry = ModelCatalog.findById(modelId);
  return entry?.speakerCount ?? 0;
}
