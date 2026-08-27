import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:relagent/models/imported_model.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/providers/model_download_provider.dart';
import 'package:relagent/providers/settings_provider.dart';
import 'package:relagent/voice/imported_model_registry.dart';
import 'package:relagent/voice/model_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String dir;
  _FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationCachePath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getLibraryPath() async => null;
  @override
  Future<String?> getExternalStoragePath() async => null;
  @override
  Future<List<String>?> getExternalCachePaths() async => null;
  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => null;
  @override
  Future<String?> getDownloadsPath() async => null;
}

/// Stub that behaves like a real filesystem scan finding nothing under the
/// catalog/downloaded-models tree, but still flips `isScanning` to false
/// asynchronously like [ModelDownloadService] does.
class _EmptyModelDownloadService extends ModelDownloadService {
  @override
  Future<Set<String>> listDownloadedModels() async => {};
  @override
  Future<int> totalStorageUsed() async => 0;
  @override
  Future<void> downloadModel(
    CatalogEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {}
  @override
  void cancelDownload(String modelId) {}
  @override
  Future<void> deleteModel(String modelId) async {}
}

/// Waits for the initial model-download scan to settle, so a test that
/// touches `defaultAsrModelId` doesn't race `SettingsNotifier`'s
/// stale-selection validation (which clears it if the id isn't downloaded
/// or imported by the time the scan completes).
Future<void> _awaitScan(ProviderContainer container) async {
  container.read(modelDownloadProvider);
  await pumpEventQueue();
}

void main() {
  late Directory tmpDir;
  late ProviderContainer container;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('settings_provider_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    await ImportedModelRegistry.init();
    await ImportedModelRegistry.add(
      ImportedModelEntry(
        id: 'imported-restart01',
        displayName: 'My Imported ASR',
        type: ModelType.asr,
        architecture: ModelArchitecture.transducer,
        languages: ['en'],
        importedAt: DateTime(2026),
      ),
    );

    SharedPreferences.setMockInitialValues({
      'user_settings':
          '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour","defaultAsrModelId":"imported-restart01"}',
    });
    final sharedPreferences = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        modelDownloadServiceProvider.overrideWithValue(
          _EmptyModelDownloadService(),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await tmpDir.delete(recursive: true);
  });

  test(
    'selected imported model survives the post-startup download scan',
    () async {
      // Reading the settings immediately after "restart" should restore the
      // previously selected imported model id.
      expect(
        container.read(settingsProvider).defaultAsrModelId,
        'imported-restart01',
      );

      // Let the initial model-download filesystem scan complete, which is
      // what triggers SettingsNotifier's stale-selection validation.
      container.read(modelDownloadProvider);
      await pumpEventQueue();

      expect(container.read(modelDownloadProvider).isScanning, isFalse);
      expect(
        container.read(settingsProvider).defaultAsrModelId,
        'imported-restart01',
        reason:
            'Imported models are not tracked in ModelDownloadState.downloadedModels, '
            'so validation must not clear their selection.',
      );
    },
  );

  group('TTS language preferences', () {
    test('assigning a model to a language persists the preference', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.assignTtsModelToLanguage('fr', 'kokoro-fr');

      expect(
        container.read(settingsProvider).ttsLanguagePreferences,
        {'fr': 'kokoro-fr'},
      );
    });

    test('reassigning a language replaces the previous model', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.assignTtsModelToLanguage('fr', 'kokoro-fr');
      await notifier.assignTtsModelToLanguage('fr', 'other-fr-model');

      expect(
        container.read(settingsProvider).ttsLanguagePreferences,
        {'fr': 'other-fr-model'},
      );
    });

    test('removing a language preference deletes only that entry', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.assignTtsModelToLanguage('fr', 'kokoro-fr');
      await notifier.assignTtsModelToLanguage('de', 'kokoro-de');
      await notifier.removeTtsLanguagePreference('fr');

      expect(
        container.read(settingsProvider).ttsLanguagePreferences,
        {'de': 'kokoro-de'},
      );
    });

    test('setting a default model persists it', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setDefaultTtsModel('kokoro-en');

      expect(container.read(settingsProvider).defaultTtsModelId, 'kokoro-en');
    });

    test('clearing the default model sets it to null', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setDefaultTtsModel('kokoro-en');
      await notifier.setDefaultTtsModel(null);

      expect(container.read(settingsProvider).defaultTtsModelId, isNull);
    });

    test(
      'clearModelSelection removes language assignments and default pointing to the deleted model',
      () async {
        final notifier = container.read(settingsProvider.notifier);
        await notifier.assignTtsModelToLanguage('fr', 'kokoro-fr');
        await notifier.assignTtsModelToLanguage('de', 'kokoro-de');
        await notifier.setDefaultTtsModel('kokoro-fr');

        await notifier.clearModelSelection('kokoro-fr');

        final settings = container.read(settingsProvider);
        expect(settings.ttsLanguagePreferences, {'de': 'kokoro-de'});
        expect(settings.defaultTtsModelId, isNull);
      },
    );

    test('preferences survive a reload from persisted storage', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.assignTtsModelToLanguage('fr', 'kokoro-fr');
      await notifier.setDefaultTtsModel('kokoro-en');

      final sharedPreferences = await SharedPreferences.getInstance();
      final reloaded = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
          modelDownloadServiceProvider.overrideWithValue(
            _EmptyModelDownloadService(),
          ),
        ],
      );
      addTearDown(reloaded.dispose);

      final settings = reloaded.read(settingsProvider);
      expect(settings.ttsLanguagePreferences, {'fr': 'kokoro-fr'});
      expect(settings.defaultTtsModelId, 'kokoro-en');
    });
  });

  group('ASR quick-pick', () {
    test('enabling a model adds it to the quick-pick set', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setAsrQuickPickEnabled('whisper-fr', true);

      expect(container.read(settingsProvider).asrQuickPickModelIds, [
        'whisper-fr',
      ]);
    });

    test(
      'a multi-language model is a single entry, not one per language',
      () async {
        final notifier = container.read(settingsProvider.notifier);
        await notifier.setAsrQuickPickEnabled('parakeet-multi', true);

        expect(container.read(settingsProvider).asrQuickPickModelIds, [
          'parakeet-multi',
        ]);
      },
    );

    test('enabling an already-enabled model does not duplicate it', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setAsrQuickPickEnabled('whisper-fr', true);
      await notifier.setAsrQuickPickEnabled('whisper-fr', true);

      expect(container.read(settingsProvider).asrQuickPickModelIds, [
        'whisper-fr',
      ]);
    });

    test('disabling a model removes only that entry', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setAsrQuickPickEnabled('whisper-fr', true);
      await notifier.setAsrQuickPickEnabled('whisper-de', true);
      await notifier.setAsrQuickPickEnabled('whisper-fr', false);

      expect(container.read(settingsProvider).asrQuickPickModelIds, [
        'whisper-de',
      ]);
    });

    test('setting a default model persists it', () async {
      await _awaitScan(container);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setDefaultAsrModel('whisper-en');

      expect(container.read(settingsProvider).defaultAsrModelId, 'whisper-en');
    });

    test('clearing the default model sets it to null', () async {
      await _awaitScan(container);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setDefaultAsrModel('whisper-en');
      await notifier.setDefaultAsrModel(null);

      expect(container.read(settingsProvider).defaultAsrModelId, isNull);
    });

    test(
      'clearModelSelection removes the quick-pick entry and default pointing to the deleted model',
      () async {
        await _awaitScan(container);
        final notifier = container.read(settingsProvider.notifier);
        await notifier.setAsrQuickPickEnabled('whisper-fr', true);
        await notifier.setAsrQuickPickEnabled('whisper-de', true);
        await notifier.setDefaultAsrModel('whisper-fr');

        await notifier.clearModelSelection('whisper-fr');

        final settings = container.read(settingsProvider);
        expect(settings.asrQuickPickModelIds, ['whisper-de']);
        expect(settings.defaultAsrModelId, isNull);
      },
    );

    test('preferences survive a reload from persisted storage', () async {
      await _awaitScan(container);
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setAsrQuickPickEnabled('whisper-fr', true);
      await notifier.setDefaultAsrModel('whisper-en');

      final sharedPreferences = await SharedPreferences.getInstance();
      final reloaded = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
          modelDownloadServiceProvider.overrideWithValue(
            _EmptyModelDownloadService(),
          ),
        ],
      );
      addTearDown(reloaded.dispose);

      final settings = reloaded.read(settingsProvider);
      expect(settings.asrQuickPickModelIds, ['whisper-fr']);
      expect(settings.defaultAsrModelId, 'whisper-en');
    });

    test(
      'defaultAsrModelId migrates from the legacy selectedAsrModelId key',
      () async {
        SharedPreferences.setMockInitialValues({
          'user_settings':
              '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour","selectedAsrModelId":"legacy-model"}',
        });
        final sharedPreferences = await SharedPreferences.getInstance();
        final migrated = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sharedPreferences),
            modelDownloadServiceProvider.overrideWithValue(
              _EmptyModelDownloadService(),
            ),
          ],
        );
        addTearDown(migrated.dispose);

        expect(
          migrated.read(settingsProvider).defaultAsrModelId,
          'legacy-model',
        );
      },
    );
  });
}
