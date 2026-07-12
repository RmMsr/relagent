import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:relagent/models/imported_model.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/providers/model_download_provider.dart';
import 'package:relagent/voice/imported_model_registry.dart';
import 'package:relagent/voice/model_resolver.dart';

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

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('resolver_imported_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    await ModelCatalog.init(jsonOverride: '[]');
    await ImportedModelRegistry.init();
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  Future<void> _createCompleteMarker(String id, ModelType type) async {
    final typeDir = type == ModelType.asr ? 'asr' : 'tts';
    final dir = Directory(
      p.join(tmpDir.path, 'imported_models', typeDir, id),
    );
    await dir.create(recursive: true);
    await File(p.join(dir.path, '.complete')).writeAsString('done');
  }

  test('resolveAsrMetadata falls back to imported model when catalog miss', () async {
    const id = 'imported-resolver01';
    await ImportedModelRegistry.add(ImportedModelEntry(
      id: id,
      displayName: 'My ASR',
      type: ModelType.asr,
      architecture: ModelArchitecture.transducer,
      languages: ['en'],
      importedAt: DateTime(2026),
    ));
    await _createCompleteMarker(id, ModelType.asr);

    final settings = Settings.defaults().copyWith(selectedAsrModelId: id);
    final result = await resolveAsrMetadata(settings, const ModelDownloadState());

    expect(result, isNotNull);
    expect(result!.modelId, id);
    expect(result.architecture, ModelArchitecture.transducer);
  });

  test('resolveAsrMetadata returns null for imported model without .complete marker', () async {
    const id = 'imported-resolver02';
    await ImportedModelRegistry.add(ImportedModelEntry(
      id: id,
      displayName: 'My ASR',
      type: ModelType.asr,
      architecture: ModelArchitecture.transducer,
      languages: [],
      importedAt: DateTime(2026),
    ));
    // No .complete marker created

    final settings = Settings.defaults().copyWith(selectedAsrModelId: id);
    final result = await resolveAsrMetadata(settings, const ModelDownloadState());
    expect(result, isNull);
  });

  test('resolveTtsModel falls back to imported model when catalog miss', () async {
    const id = 'imported-resolver03';
    await ImportedModelRegistry.add(ImportedModelEntry(
      id: id,
      displayName: 'My TTS',
      type: ModelType.tts,
      architecture: ModelArchitecture.vitsPiper,
      languages: ['de'],
      importedAt: DateTime(2026),
    ));
    await _createCompleteMarker(id, ModelType.tts);

    final settings = Settings.defaults().copyWith(selectedTtsModelId: id);
    final result = await resolveTtsModel(settings, const ModelDownloadState());

    expect(result, isNotNull);
    expect(result!.modelId, id);
    expect(result.architecture, ModelArchitecture.vitsPiper);
  });
}
