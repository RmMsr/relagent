import 'dart:io';

import 'package:path/path.dart' as p;

import '/models/model_catalog.dart';
import '/models/settings.dart';
import '/providers/model_download_provider.dart';
import '/speech_recognition/asr_metadata.dart';
import '/voice/download_model_loader.dart';
import '/voice/imported_model_loader.dart';
import '/voice/imported_model_registry.dart';

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

/// Resolve the selected ASR model to metadata, or null if no model available.
Future<AsrModelMetadata?> resolveAsrMetadata(
  Settings settings,
  ModelDownloadState downloadState,
) async {
  final modelId = settings.selectedAsrModelId;
  if (modelId == null) return null;

  final catalogEntry = ModelCatalog.findById(modelId);
  if (catalogEntry != null) {
    if (catalogEntry.type != ModelType.asr) return null;
    if (!downloadState.isDownloaded(modelId)) return null;
    final loader = DownloadModelLoader(catalogEntry);
    return AsrModelMetadata(
      architecture: catalogEntry.architecture,
      fileStructure: catalogEntry.fileStructure,
      loader: loader,
      modelId: catalogEntry.id,
      language: catalogEntry.languages.isNotEmpty
          ? catalogEntry.languages.first
          : null,
    );
  }

  final importedEntry = ImportedModelRegistry.findById(modelId);
  if (importedEntry == null) return null;
  if (importedEntry.type != ModelType.asr) return null;

  final loader = ImportedModelLoader(importedEntry);
  if (!await loader.isModelAvailable(modelId)) return null;

  final modelRoot = await loader.loadModel(modelId);
  final fileStructure = await _buildImportedAsrFileStructure(modelRoot);

  return AsrModelMetadata(
    architecture: importedEntry.architecture,
    fileStructure: fileStructure,
    loader: loader,
    modelId: importedEntry.id,
    language: importedEntry.languages.isNotEmpty
        ? importedEntry.languages.first
        : null,
  );
}

/// Resolve the selected TTS model to a ResolvedTtsModel with absolute paths,
/// or null if no model available. Resolves all paths in the main isolate.
Future<ResolvedTtsModel?> resolveTtsModel(
  Settings settings,
  ModelDownloadState downloadState,
) async {
  final modelId = settings.selectedTtsModelId;
  if (modelId == null) return null;

  final catalogEntry = ModelCatalog.findById(modelId);
  if (catalogEntry != null) {
    if (catalogEntry.type != ModelType.tts) return null;
    if (!downloadState.isDownloaded(modelId)) return null;

    final loader = DownloadModelLoader(catalogEntry);
    final resolvedPaths = <String, String>{};

    for (final logicalName in catalogEntry.fileStructure.keys) {
      final relativePath = catalogEntry.fileStructure[logicalName]!;
      if (logicalName == 'dataDir') {
        resolvedPaths[logicalName] = await loader.loadModelDirectory(
          catalogEntry.id,
          relativePath,
        );
      } else {
        resolvedPaths[logicalName] = await loader.loadModelFile(
          catalogEntry.id,
          relativePath,
        );
      }
    }

    return ResolvedTtsModel(
      modelId: catalogEntry.id,
      architecture: catalogEntry.architecture,
      resolvedPaths: resolvedPaths,
    );
  }

  final importedEntry = ImportedModelRegistry.findById(modelId);
  if (importedEntry == null) return null;
  if (importedEntry.type != ModelType.tts) return null;

  final loader = ImportedModelLoader(importedEntry);
  if (!await loader.isModelAvailable(modelId)) return null;

  final modelRoot = await loader.loadModel(modelId);
  final resolvedPaths = await _resolveImportedTtsPaths(
    modelRoot,
    importedEntry.architecture,
  );

  _validateImportedTtsPaths(resolvedPaths, importedEntry.architecture);

  return ResolvedTtsModel(
    modelId: importedEntry.id,
    architecture: importedEntry.architecture,
    resolvedPaths: resolvedPaths,
  );
}

/// Scan an extracted model directory and build the resolvedPaths map expected
/// by [_buildConfigFromResolvedPaths] in the TTS isolate worker.
Future<Map<String, String>> _resolveImportedTtsPaths(
  String modelRoot,
  ModelArchitecture architecture,
) async {
  final dir = Directory(modelRoot);
  final entries = await dir.list(recursive: true).toList();

  String? findFile(bool Function(String name) test) {
    for (final e in entries) {
      if (e is File && test(p.basename(e.path).toLowerCase())) return e.path;
    }
    return null;
  }

  String? findDir(bool Function(String name) test) {
    for (final e in entries) {
      if (e is Directory && test(p.basename(e.path).toLowerCase())) {
        return e.path;
      }
    }
    return null;
  }

  final paths = <String, String>{};

  switch (architecture) {
    case ModelArchitecture.vitsPiper:
      paths['model'] = findFile((n) => n.endsWith('.onnx')) ?? '';
      paths['tokens'] = findFile((n) => n == 'tokens.txt') ?? '';
      paths['dataDir'] = findDir((n) => n == 'espeak-ng-data') ?? '';

    case ModelArchitecture.kokoro:
      paths['model'] = findFile((n) => n.endsWith('.onnx')) ?? '';
      paths['voices'] = findFile((n) => n == 'voices.bin') ?? '';
      paths['tokens'] = findFile((n) => n == 'tokens.txt') ?? '';
      paths['dataDir'] = findDir((n) => n == 'espeak-ng-data' || n == 'data') ?? '';
      final lexicon = findFile((n) => n.contains('lexicon'));
      if (lexicon != null) paths['lexicon'] = lexicon;

    case ModelArchitecture.pocket:
      paths['lmFlow'] = findFile((n) => n.contains('lm') && n.contains('flow')) ?? '';
      paths['lmMain'] = findFile((n) => n.contains('lm') && n.contains('main')) ?? '';
      paths['encoder'] = findFile((n) => n.contains('encoder')) ?? '';
      paths['decoder'] = findFile((n) => n.contains('decoder')) ?? '';
      paths['textConditioner'] = findFile((n) => n.contains('text_conditioner') || n.contains('textconditioner')) ?? '';
      paths['vocabJson'] = findFile((n) => n.contains('vocab') && n.endsWith('.json')) ?? '';
      paths['tokenScoresJson'] = findFile((n) => n.contains('token_scores') || n.contains('tokenscores')) ?? '';

    default:
      break;
  }

  return paths;
}

/// Scan an imported ASR model directory and build a fileStructure map of
/// logical name → path relative to [modelRoot].
Future<Map<String, String>> _buildImportedAsrFileStructure(
  String modelRoot,
) async {
  final dir = Directory(modelRoot);
  if (!await dir.exists()) return {};

  final structure = <String, String>{};
  await for (final entity in dir.list(recursive: true)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: modelRoot);
    final name = p.basename(rel);
    if (name.startsWith('.')) continue;

    if (name.endsWith('.onnx')) {
      if (rel.contains('encoder')) {
        structure.putIfAbsent('encoder', () => rel);
      } else if (rel.contains('decoder')) {
        structure.putIfAbsent('decoder', () => rel);
      } else if (rel.contains('joiner')) {
        structure.putIfAbsent('joiner', () => rel);
      } else {
        structure.putIfAbsent('model', () => rel);
      }
    } else if (name == 'tokens.txt' || name.endsWith('-tokens.txt')) {
      // sherpa-onnx's whisper export names this "<model-name>-tokens.txt"
      // rather than the bare "tokens.txt" every other architecture uses.
      structure['tokens'] = rel;
    }
  }
  return structure;
}

/// Throw if any required path for [architecture] is missing (empty string).
/// This catches "wrong model layout" before sherpa-onnx can trigger a native abort.
void _validateImportedTtsPaths(
  Map<String, String> paths,
  ModelArchitecture architecture,
) {
  List<String> required;
  switch (architecture) {
    case ModelArchitecture.vitsPiper:
      required = ['model', 'tokens', 'dataDir'];
    case ModelArchitecture.kokoro:
      required = ['model', 'voices', 'tokens', 'dataDir'];
    case ModelArchitecture.pocket:
      required = [
        'lmFlow', 'lmMain', 'encoder', 'decoder',
        'textConditioner', 'vocabJson', 'tokenScoresJson',
      ];
    default:
      return;
  }
  for (final key in required) {
    if (paths[key]?.isEmpty ?? true) {
      throw Exception('Required model file "$key" not found in imported model');
    }
  }
}

/// Get the speaker count for the currently selected TTS model.
/// Returns 0 when no model is selected or for imported models (unknown count).
int getSelectedTtsSpeakerCount(Settings settings) {
  final modelId = settings.selectedTtsModelId;
  if (modelId == null) return 0;

  final catalogEntry = ModelCatalog.findById(modelId);
  if (catalogEntry != null) return catalogEntry.speakerCount;

  // Imported models have unknown speaker count; default to 0 (single speaker).
  final importedEntry = ImportedModelRegistry.findById(modelId);
  return importedEntry != null ? 0 : 0;
}
