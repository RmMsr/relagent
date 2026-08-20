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
          '{"simpleChatBaseUrl":"http://localhost:1234/api/v1","simpleChatModel":"test-model","primeMessage":"test","ttsSpeakerId":0,"ttsSpeed":1.0,"voiceMode":"silent","backgroundListeningDuration":"oneHour","selectedAsrModelId":"imported-restart01"}',
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
        container.read(settingsProvider).selectedAsrModelId,
        'imported-restart01',
      );

      // Let the initial model-download filesystem scan complete, which is
      // what triggers SettingsNotifier's stale-selection validation.
      container.read(modelDownloadProvider);
      await pumpEventQueue();

      expect(container.read(modelDownloadProvider).isScanning, isFalse);
      expect(
        container.read(settingsProvider).selectedAsrModelId,
        'imported-restart01',
        reason:
            'Imported models are not tracked in ModelDownloadState.downloadedModels, '
            'so validation must not clear their selection.',
      );
    },
  );
}
