import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/model_download_provider.dart';
import 'package:relagent/voice/model_resolver.dart';

class _FakeSupportPathProvider extends PathProviderPlatform {
  final String basePath;
  _FakeSupportPathProvider(this.basePath);

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
}

void main() {
  setUpAll(() async {
    final fixture = await File(
      'test/fixtures/voice-models.json',
    ).readAsString();
    await ModelCatalog.init(jsonOverride: fixture);
  });

  // --- ASR fallback chain (task 10.5, revised by design D17 — session
  // override -> persisted default -> first downloaded model -> none) ---

  group('resolveAsrMetadata — fallback chain', () {
    test('returns null when nothing is configured and nothing is downloaded', () async {
      final settings = Settings.defaults();
      final downloadState = const ModelDownloadState();

      final result = await resolveAsrMetadata(settings, downloadState);
      expect(result, isNull);
    });

    test('returns null when default model is not in catalog', () async {
      final settings = Settings.defaults().copyWith(
        defaultAsrModelId: 'unknown-model-id',
      );
      final downloadState = const ModelDownloadState();

      final result = await resolveAsrMetadata(settings, downloadState);
      expect(result, isNull);
    });

    test('returns null when model is in catalog but not downloaded', () async {
      final settings = Settings.defaults().copyWith(
        defaultAsrModelId: 'zipformer-en-kroko',
      );
      final downloadState = const ModelDownloadState(downloadedModels: {});

      final result = await resolveAsrMetadata(settings, downloadState);
      expect(
        result,
        isNull,
        reason: 'Default model not in downloadedModels should return null',
      );
    });

    test('returns metadata for the persisted default when downloaded', () async {
      final settings = Settings.defaults().copyWith(
        defaultAsrModelId: 'zipformer-en-kroko',
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
          defaultAsrModelId: 'kokoro-en-v0_19-int8',
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

    test(
      'falls back to the first downloaded ASR model when nothing is configured',
      () async {
        final settings = Settings.defaults();
        final downloadState = const ModelDownloadState(
          downloadedModels: {'zipformer-en-kroko'},
        );

        final result = await resolveAsrMetadata(settings, downloadState);
        expect(result?.modelId, 'zipformer-en-kroko');
      },
    );

    test(
      'session override takes priority over the persisted default',
      () async {
        final settings = Settings.defaults().copyWith(
          defaultAsrModelId: 'zipformer-en-kroko',
        );
        final downloadState = const ModelDownloadState(
          downloadedModels: {'zipformer-en-kroko', 'zipformer-de-kroko'},
        );

        final result = await resolveAsrMetadata(
          settings,
          downloadState,
          sessionOverride: 'zipformer-de-kroko',
        );
        expect(result?.modelId, 'zipformer-de-kroko');
      },
    );
  });

  // --- Session override / default / first-downloaded selection ---

  group('selectActiveAsrModelId — fallback chain', () {
    test('uses the session override when set', () {
      final settings = Settings.defaults().copyWith(
        defaultAsrModelId: 'zipformer-en-kroko',
      );

      final modelId = selectActiveAsrModelId(settings, 'zipformer-de-kroko');
      expect(modelId, 'zipformer-de-kroko');
    });

    test('falls back to the persisted default with no session override', () {
      final settings = Settings.defaults().copyWith(
        defaultAsrModelId: 'zipformer-en-kroko',
      );

      final modelId = selectActiveAsrModelId(settings, null);
      expect(modelId, 'zipformer-en-kroko');
    });

    test('returns null when neither is set', () {
      final settings = Settings.defaults();

      final modelId = selectActiveAsrModelId(settings, null);
      expect(modelId, isNull);
    });
  });

  group('firstDownloadedAsrModelId', () {
    test('returns the first downloaded catalog ASR model', () {
      final downloadState = const ModelDownloadState(
        downloadedModels: {'zipformer-en-kroko'},
      );

      expect(firstDownloadedAsrModelId(downloadState), 'zipformer-en-kroko');
    });

    test('returns null when no ASR model is downloaded', () {
      final downloadState = const ModelDownloadState();

      expect(firstDownloadedAsrModelId(downloadState), isNull);
    });
  });

  group('quickPickAsrEntries', () {
    test('returns entries for usable quick-pick models, sorted by name', () {
      final settings = Settings.defaults().copyWith(
        asrQuickPickModelIds: ['zipformer-en-kroko', 'zipformer-de-kroko'],
      );
      final downloadState = const ModelDownloadState(
        downloadedModels: {'zipformer-en-kroko', 'zipformer-de-kroko'},
      );

      // Sorted by display name ("English - Zipformer" before "German -
      // Zipformer"), not by id.
      final entries = quickPickAsrEntries(settings, downloadState);
      expect(entries.map((e) => e.id).toList(), [
        'zipformer-en-kroko',
        'zipformer-de-kroko',
      ]);
    });

    test('excludes a quick-pick model that is not downloaded', () {
      final settings = Settings.defaults().copyWith(
        asrQuickPickModelIds: ['zipformer-en-kroko', 'zipformer-de-kroko'],
      );
      final downloadState = const ModelDownloadState(
        downloadedModels: {'zipformer-en-kroko'},
      );

      final entries = quickPickAsrEntries(settings, downloadState);
      expect(entries.map((e) => e.id).toList(), ['zipformer-en-kroko']);
    });

    test('returns an empty list when nothing is quick-picked', () {
      final settings = Settings.defaults();
      final downloadState = const ModelDownloadState(
        downloadedModels: {'zipformer-en-kroko'},
      );

      expect(quickPickAsrEntries(settings, downloadState), isEmpty);
    });
  });

  group('languageCoverageLabel', () {
    test('joins up to 3 languages', () {
      expect(languageCoverageLabel(['en']), 'en');
      expect(languageCoverageLabel(['en', 'de', 'fr']), 'en, de, fr');
    });

    test('summarizes more than 3 languages as a count', () {
      expect(languageCoverageLabel(['en', 'de', 'fr', 'es']), '4 languages');
    });

    test('shows a friendly label for the unenumerable multi sentinel', () {
      expect(languageCoverageLabel(['multi']), 'Any language');
    });
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

  // --- Language-aware TTS selection & fallback chain ---

  group('selectTtsModelIdForLanguage — fallback chain', () {
    test('uses the model assigned to the language when available', () {
      final settings = Settings.defaults().copyWith(
        ttsLanguagePreferences: {'de': 'piper-de-thorsten-medium-int8'},
        defaultTtsModelId: 'kokoro-en-v0_19-int8',
      );
      final downloadState = const ModelDownloadState(
        downloadedModels: {
          'piper-de-thorsten-medium-int8',
          'kokoro-en-v0_19-int8',
        },
      );

      final modelId = selectTtsModelIdForLanguage(
        'de',
        settings,
        downloadState,
      );
      expect(modelId, 'piper-de-thorsten-medium-int8');
    });

    test('falls back to the device default when no language match', () {
      final settings = Settings.defaults().copyWith(
        ttsLanguagePreferences: {'de': 'piper-de-thorsten-medium-int8'},
        defaultTtsModelId: 'kokoro-en-v0_19-int8',
      );
      final downloadState = const ModelDownloadState(
        downloadedModels: {
          'piper-de-thorsten-medium-int8',
          'kokoro-en-v0_19-int8',
        },
      );

      final modelId = selectTtsModelIdForLanguage(
        'fr',
        settings,
        downloadState,
      );
      expect(modelId, 'kokoro-en-v0_19-int8');
    });

    test('uses the device default when the message has no language code', () {
      final settings = Settings.defaults().copyWith(
        defaultTtsModelId: 'kokoro-en-v0_19-int8',
      );
      final downloadState = const ModelDownloadState(
        downloadedModels: {'kokoro-en-v0_19-int8'},
      );

      final modelId = selectTtsModelIdForLanguage(
        null,
        settings,
        downloadState,
      );
      expect(modelId, 'kokoro-en-v0_19-int8');
    });

    test(
      'falls back to the first downloaded TTS model when no default is set',
      () {
        final settings = Settings.defaults();
        final downloadState = const ModelDownloadState(
          downloadedModels: {'piper-en-lessac-medium-int8'},
        );

        final modelId = selectTtsModelIdForLanguage(
          'de',
          settings,
          downloadState,
        );
        expect(modelId, 'piper-en-lessac-medium-int8');
      },
    );

    test('returns null when no TTS model is available at all', () {
      final settings = Settings.defaults();
      final downloadState = const ModelDownloadState();

      final modelId = selectTtsModelIdForLanguage(
        'de',
        settings,
        downloadState,
      );
      expect(modelId, isNull);
    });
  });

  group('resolveTtsModelForLanguage', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resolver_lang_test_');
      PathProviderPlatform.instance = _FakeSupportPathProvider(tempDir.path);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('resolves paths for the language-assigned model', () async {
      const modelId = 'piper-de-thorsten-medium-int8';
      final entry = ModelCatalog.findById(modelId)!;

      final modelDir = Directory(
        p.join(tempDir.path, 'models', 'tts', modelId),
      );
      await modelDir.create(recursive: true);
      for (final fileEntry in entry.fileStructure.entries) {
        if (fileEntry.key == 'dataDir') {
          await Directory(
            p.join(modelDir.path, fileEntry.value),
          ).create(recursive: true);
        } else {
          await File(
            p.join(modelDir.path, fileEntry.value),
          ).writeAsString('fake');
        }
      }

      final settings = Settings.defaults().copyWith(
        ttsLanguagePreferences: {'de': modelId},
      );
      final downloadState = const ModelDownloadState(
        downloadedModels: {modelId},
      );

      final result = await resolveTtsModelForLanguage(
        'de',
        settings,
        downloadState,
      );
      expect(result, isNotNull);
      expect(result!.modelId, modelId);
    });

    test('returns null when nothing is available (skip playback)', () async {
      final settings = Settings.defaults();
      final downloadState = const ModelDownloadState();

      final result = await resolveTtsModelForLanguage(
        'de',
        settings,
        downloadState,
      );
      expect(result, isNull);
    });
  });

  // --- TTS with Piper VITS resolved paths (task 10.4) ---

  group('resolveTtsModel — Piper VITS model (task 10.4)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resolver_test_');
      PathProviderPlatform.instance = _FakeSupportPathProvider(tempDir.path);
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
        defaultAsrModelId: 'omnilingual-asr-300m-ctc-int8',
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
