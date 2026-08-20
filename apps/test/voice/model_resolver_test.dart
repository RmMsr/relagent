import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/model_download_provider.dart';
import 'package:relagent/voice/model_resolver.dart';

class _FakeCachePathProvider extends PathProviderPlatform {
  final String cachePath;
  _FakeCachePathProvider(this.cachePath);

  @override
  Future<String?> getApplicationCachePath() async => cachePath;
}

void main() {
  setUpAll(() async {
    final fixture = await File(
      'test/fixtures/voice-models.json',
    ).readAsString();
    await ModelCatalog.init(jsonOverride: fixture);
  });

  // --- ASR fallback chain (task 10.5) ---

  group('resolveAsrMetadata — fallback chain', () {
    test('returns null when no ASR model is selected (unavailable)', () async {
      final settings = Settings.defaults();
      final downloadState = const ModelDownloadState();

      final result = await resolveAsrMetadata(settings, downloadState);
      expect(result, isNull);
    });

    test('returns null when selected model is not in catalog', () async {
      final settings = Settings.defaults().copyWith(
        selectedAsrModelId: 'unknown-model-id',
      );
      final downloadState = const ModelDownloadState();

      final result = await resolveAsrMetadata(settings, downloadState);
      expect(result, isNull);
    });

    test('returns null when model is in catalog but not downloaded', () async {
      final settings = Settings.defaults().copyWith(
        selectedAsrModelId: 'zipformer-en-kroko',
      );
      final downloadState = const ModelDownloadState(downloadedModels: {});

      final result = await resolveAsrMetadata(settings, downloadState);
      expect(
        result,
        isNull,
        reason: 'Selected model not in downloadedModels should return null',
      );
    });

    test('returns metadata when model is selected and downloaded', () async {
      final settings = Settings.defaults().copyWith(
        selectedAsrModelId: 'zipformer-en-kroko',
      );
      final downloadState = const ModelDownloadState(
        downloadedModels: {'zipformer-en-kroko'},
      );

      final result = await resolveAsrMetadata(settings, downloadState);
      expect(result, isNotNull);
      expect(result!.modelId, 'zipformer-en-kroko');
      expect(result.architecture, ModelArchitecture.transducer);
    });

    test(
      'returns null when TTS model ID is passed for ASR (wrong type)',
      () async {
        final settings = Settings.defaults().copyWith(
          selectedAsrModelId: 'kokoro-en-v0_19-int8',
        );
        final downloadState = const ModelDownloadState(
          downloadedModels: {'kokoro-en-v0_19-int8'},
        );

        final result = await resolveAsrMetadata(settings, downloadState);
        expect(
          result,
          isNull,
          reason: 'TTS model ID should not resolve as ASR metadata',
        );
      },
    );
  });

  // --- TTS fallback chain ---

  group('resolveTtsModel — fallback chain', () {
    test('returns null when no TTS model is selected', () async {
      final settings = Settings.defaults();
      final downloadState = const ModelDownloadState();

      final result = await resolveTtsModel(settings, downloadState);
      expect(result, isNull);
    });

    test('returns null when selected model is not downloaded', () async {
      final settings = Settings.defaults().copyWith(
        selectedTtsModelId: 'piper-en-lessac-medium-int8',
      );
      final downloadState = const ModelDownloadState(downloadedModels: {});

      final result = await resolveTtsModel(settings, downloadState);
      expect(result, isNull);
    });
  });

  // --- TTS with Piper VITS resolved paths (task 10.4) ---

  group('resolveTtsModel — Piper VITS model (task 10.4)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resolver_test_');
      PathProviderPlatform.instance = _FakeCachePathProvider(tempDir.path);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('resolves Piper model file paths from download storage', () async {
      const modelId = 'piper-en-lessac-medium-int8';
      final entry = ModelCatalog.findById(modelId)!;
      expect(
        entry.architecture,
        ModelArchitecture.vitsPiper,
        reason: 'Test requires a Piper VITS model in the catalog',
      );

      // Create fake model files in the download storage directory.
      // Keys named 'dataDir' point to directories; all others are files.
      final modelDir = Directory(
        p.join(tempDir.path, 'models', 'tts', modelId),
      );
      await modelDir.create(recursive: true);
      for (final entry_ in entry.fileStructure.entries) {
        final relativePath = entry_.value;
        if (entry_.key == 'dataDir') {
          await Directory(
            p.join(modelDir.path, relativePath),
          ).create(recursive: true);
        } else {
          await File(p.join(modelDir.path, relativePath)).writeAsString('fake');
        }
      }

      final settings = Settings.defaults().copyWith(
        selectedTtsModelId: modelId,
      );
      final downloadState = ModelDownloadState(downloadedModels: {modelId});

      final result = await resolveTtsModel(settings, downloadState);
      expect(result, isNotNull);
      expect(result!.modelId, modelId);
      expect(result.architecture, ModelArchitecture.vitsPiper);
      expect(result.resolvedPaths, contains('model'));
      expect(result.resolvedPaths, contains('tokens'));
      expect(result.resolvedPaths, contains('dataDir'));
      // Resolved path points to the actual filename from the fileStructure
      expect(
        result.resolvedPaths['model'],
        endsWith(entry.fileStructure['model']!),
      );
    });
  });

  // --- CTC architecture (task 10.3) ---

  group('ASR CTC architecture (task 10.3)', () {
    test('resolves metadata for a downloaded CTC model', () async {
      final settings = Settings.defaults().copyWith(
        selectedAsrModelId: 'omnilingual-asr-300m-ctc-int8',
      );
      final downloadState = const ModelDownloadState(
        downloadedModels: {'omnilingual-asr-300m-ctc-int8'},
      );

      final result = await resolveAsrMetadata(settings, downloadState);
      expect(result, isNotNull);
      expect(result!.modelId, 'omnilingual-asr-300m-ctc-int8');
      expect(result.architecture, ModelArchitecture.ctc);

      final entry = ModelCatalog.findById('omnilingual-asr-300m-ctc-int8');
      expect(entry!.fileStructure, containsPair('encoder', 'model.int8.onnx'));
    });
  });

  // --- speaker count helper ---

  group('getSelectedTtsSpeakerCount', () {
    test('returns 0 when no model is selected', () {
      // No bundled fallback — caller must handle 0 as "no TTS available".
      final settings = Settings.defaults();
      expect(getSelectedTtsSpeakerCount(settings), 0);
    });

    test('returns speaker count from catalog entry', () {
      final settings = Settings.defaults().copyWith(
        selectedTtsModelId: 'kokoro-en-v0_19-int8',
      );
      final entry = ModelCatalog.findById('kokoro-en-v0_19-int8')!;
      expect(getSelectedTtsSpeakerCount(settings), entry.speakerCount);
    });

    test('returns 1 for single-speaker Piper model', () {
      final settings = Settings.defaults().copyWith(
        selectedTtsModelId: 'piper-en-lessac-medium-int8',
      );
      expect(getSelectedTtsSpeakerCount(settings), 1);
    });
  });
}
