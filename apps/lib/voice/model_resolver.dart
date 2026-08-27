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

/// Selects which ASR model id to use: this session's quick-pick override
/// (if set), else the persisted device default. Pure/synchronous. Does not
/// fall further to "first downloaded" — see [resolveAsrMetadata], which adds
/// that step since it's the one place that also has [ModelDownloadState] to
/// determine what's actually downloaded (design D17).
String? selectActiveAsrModelId(Settings settings, String? sessionOverride) {
  return sessionOverride ?? settings.defaultAsrModelId;
}

/// First downloaded ASR model, catalog entries before imported ones — the
/// last-resort fallback when neither a session override nor a device
/// default is set. Mirrors [selectTtsModelIdForLanguage]'s equivalent step.
String? firstDownloadedAsrModelId(ModelDownloadState downloadState) {
  final downloadedCatalogAsr = ModelCatalog.byType(
    ModelType.asr,
  ).where((entry) => downloadState.isDownloaded(entry.id));
  if (downloadedCatalogAsr.isNotEmpty) return downloadedCatalogAsr.first.id;

  final importedAsr = ImportedModelRegistry.byType(ModelType.asr);
  if (importedAsr.isNotEmpty) return importedAsr.first.id;

  return null;
}

/// Resolve the ASR model to use — session override -> device default ->
/// first downloaded model -> none (design D17) — to metadata, or null if no
/// model available.
Future<AsrModelMetadata?> resolveAsrMetadata(
  Settings settings,
  ModelDownloadState downloadState, {
  String? sessionOverride,
}) async {
  final modelId =
      selectActiveAsrModelId(settings, sessionOverride) ??
      firstDownloadedAsrModelId(downloadState);
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
  return _resolveTtsModelById(modelId, downloadState);
}

/// Selects which TTS model id to use for [languageCode], following the
/// device-local fallback chain: language assignment -> device default ->
/// first downloaded TTS model -> none. Pure/synchronous: does not touch
/// the filesystem (see [resolveTtsModelForLanguage] for path resolution).
String? selectTtsModelIdForLanguage(
  String? languageCode,
  Settings settings,
  ModelDownloadState downloadState,
) {
  final assigned = languageCode == null
      ? null
      : settings.ttsLanguagePreferences[languageCode];
  if (assigned != null) return assigned;

  if (settings.defaultTtsModelId != null) return settings.defaultTtsModelId;

  final downloadedCatalogTts = ModelCatalog.byType(
    ModelType.tts,
  ).where((entry) => downloadState.isDownloaded(entry.id));
  if (downloadedCatalogTts.isNotEmpty) return downloadedCatalogTts.first.id;

  final importedTts = ImportedModelRegistry.byType(ModelType.tts);
  if (importedTts.isNotEmpty) return importedTts.first.id;

  return null;
}

/// Resolve the TTS model to use for [languageCode] to a [ResolvedTtsModel]
/// with absolute paths, following the same fallback chain as
/// [selectTtsModelIdForLanguage], or null if no TTS model is available at all.
Future<ResolvedTtsModel?> resolveTtsModelForLanguage(
  String? languageCode,
  Settings settings,
  ModelDownloadState downloadState,
) async {
  final modelId = selectTtsModelIdForLanguage(
    languageCode,
    settings,
    downloadState,
  );
  if (modelId == null) return null;
  return _resolveTtsModelById(modelId, downloadState);
}

Future<ResolvedTtsModel?> _resolveTtsModelById(
  String modelId,
  ModelDownloadState downloadState,
) async {
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
      paths['dataDir'] =
          findDir((n) => n == 'espeak-ng-data' || n == 'data') ?? '';
      final lexicon = findFile((n) => n.contains('lexicon'));
      if (lexicon != null) paths['lexicon'] = lexicon;

    case ModelArchitecture.pocket:
      paths['lmFlow'] =
          findFile((n) => n.contains('lm') && n.contains('flow')) ?? '';
      paths['lmMain'] =
          findFile((n) => n.contains('lm') && n.contains('main')) ?? '';
      paths['encoder'] = findFile((n) => n.contains('encoder')) ?? '';
      paths['decoder'] = findFile((n) => n.contains('decoder')) ?? '';
      paths['textConditioner'] =
          findFile(
            (n) =>
                n.contains('text_conditioner') || n.contains('textconditioner'),
          ) ??
          '';
      paths['vocabJson'] =
          findFile((n) => n.contains('vocab') && n.endsWith('.json')) ?? '';
      paths['tokenScoresJson'] =
          findFile(
            (n) => n.contains('token_scores') || n.contains('tokenscores'),
          ) ??
          '';

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
        'lmFlow',
        'lmMain',
        'encoder',
        'decoder',
        'textConditioner',
        'vocabJson',
        'tokenScoresJson',
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

/// Quick-pick ASR models that are actually usable right now (downloaded
/// catalog model or an imported model), sorted by display name for stable
/// display. Drives the mic long-press model quick-pick's gating — see the
/// `asr-language-selection` spec's "Mic Long-Press Offers a Session-Only
/// Recognition-Model Override" requirement.
List<({String id, String displayName, List<String> languages})>
quickPickAsrEntries(Settings settings, ModelDownloadState downloadState) {
  final entries = <({String id, String displayName, List<String> languages})>
  [];
  for (final modelId in settings.asrQuickPickModelIds) {
    final catalogEntry = ModelCatalog.findById(modelId);
    if (catalogEntry != null) {
      if (!downloadState.isDownloaded(modelId)) continue;
      entries.add((
        id: catalogEntry.id,
        displayName: catalogEntry.displayName,
        languages: catalogEntry.languages,
      ));
      continue;
    }
    final importedEntry = ImportedModelRegistry.findById(modelId);
    if (importedEntry != null) {
      entries.add((
        id: importedEntry.id,
        displayName: importedEntry.displayName,
        languages: importedEntry.languages,
      ));
    }
  }
  entries.sort((a, b) => a.displayName.compareTo(b.displayName));
  return entries;
}

/// Short, readable label for a model's declared language coverage — used
/// wherever a quick-pick entry needs to show what it covers without
/// dumping a raw 25-item list (e.g. a multilingual Parakeet model) or the
/// internal "multi" sentinel string.
String languageCoverageLabel(List<String> languages) {
  if (languages.length == 1 && languages.first == 'multi') {
    return 'Any language';
  }
  if (languages.length <= 3) return languages.join(', ');
  return '${languages.length} languages';
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
