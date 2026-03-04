import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/voice/model_download_service.dart';

/// Redirects path_provider cache directory to a temp directory for testing.
class _FakeCachePathProvider extends PathProviderPlatform {
  final String cachePath;
  _FakeCachePathProvider(this.cachePath);

  @override
  Future<String?> getApplicationCachePath() async => cachePath;
}

void main() {
  setUpAll(() async {
    final fixture =
        await File('test/fixtures/voice-models.json').readAsString();
    await ModelCatalog.init(jsonOverride: fixture);
  });

  group('ModelDownloadService — lifecycle', () {
    late Directory tempDir;
    late ModelDownloadService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('model_dl_test_');
      PathProviderPlatform.instance = _FakeCachePathProvider(tempDir.path);
      service = ModelDownloadService();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    // --- scanning ---

    test('listDownloadedModels returns empty when no models exist', () async {
      final models = await service.listDownloadedModels();
      expect(models, isEmpty);
    });

    test('isModelDownloaded returns false for unknown model', () async {
      final result = await service.isModelDownloaded('zipformer-en-kroko');
      expect(result, isFalse);
    });

    test('listDownloadedModels finds model with .complete marker', () async {
      await _seedFakeModel(tempDir, 'asr', 'zipformer-en-kroko');
      final models = await service.listDownloadedModels();
      expect(models, contains('zipformer-en-kroko'));
    });

    test('listDownloadedModels ignores directory without .complete marker',
        () async {
      // Simulate an interrupted download (directory exists, no marker)
      final modelDir = Directory(
        p.join(tempDir.path, 'models', 'asr', 'zipformer-en-kroko'),
      );
      await modelDir.create(recursive: true);
      await File(p.join(modelDir.path, 'encoder.onnx')).writeAsString('fake');

      final models = await service.listDownloadedModels();
      expect(models, isEmpty);
    });

    test('isModelDownloaded returns true when .complete marker exists',
        () async {
      await _seedFakeModel(tempDir, 'asr', 'zipformer-en-kroko');
      final result = await service.isModelDownloaded('zipformer-en-kroko');
      expect(result, isTrue);
    });

    test('listDownloadedModels finds models in both asr and tts subdirs',
        () async {
      await _seedFakeModel(tempDir, 'asr', 'zipformer-en-kroko');
      await _seedFakeModel(tempDir, 'tts', 'piper-en-lessac-medium-int8');

      final models = await service.listDownloadedModels();
      expect(models, containsAll(['zipformer-en-kroko', 'piper-en-lessac-medium-int8']));
    });

    // --- deletion ---

    test('deleteModel removes the model directory', () async {
      await _seedFakeModel(tempDir, 'asr', 'zipformer-en-kroko');

      final modelDir = Directory(
        p.join(tempDir.path, 'models', 'asr', 'zipformer-en-kroko'),
      );
      expect(await modelDir.exists(), isTrue);

      await service.deleteModel('zipformer-en-kroko');

      expect(await modelDir.exists(), isFalse);
    });

    test('deleteModel does nothing for non-existent model', () async {
      // Should not throw
      await expectLater(
        service.deleteModel('non-existent-model'),
        completes,
      );
    });

    test('listDownloadedModels returns empty after deletion', () async {
      await _seedFakeModel(tempDir, 'asr', 'zipformer-en-kroko');
      await service.deleteModel('zipformer-en-kroko');

      final models = await service.listDownloadedModels();
      expect(models, isEmpty);
    });

    // --- storage ---

    test('totalStorageUsed returns 0 with no models', () async {
      final bytes = await service.totalStorageUsed();
      expect(bytes, 0);
    });

    test('totalStorageUsed counts bytes in model directories', () async {
      final modelDir = Directory(
        p.join(tempDir.path, 'models', 'asr', 'test-model'),
      );
      await modelDir.create(recursive: true);
      await File(p.join(modelDir.path, 'model.onnx'))
          .writeAsBytes(List.filled(2048, 0));
      await File(p.join(modelDir.path, '.complete')).writeAsString('done');

      final bytes = await service.totalStorageUsed();
      expect(bytes, greaterThanOrEqualTo(2048));
    });

    // --- getModelPath ---

    test('getModelPath returns expected path for catalog entry', () async {
      final entry = ModelCatalog.findById('zipformer-en-kroko')!;
      final path = await service.getModelPath(entry);
      expect(path, endsWith(p.join('models', 'asr', 'zipformer-en-kroko')));
    });
  });
}

/// Creates a fake extracted model directory with a .complete marker.
Future<void> _seedFakeModel(
  Directory tempDir,
  String typeDir,
  String modelId,
) async {
  final modelDir = Directory(
    p.join(tempDir.path, 'models', typeDir, modelId),
  );
  await modelDir.create(recursive: true);
  await File(p.join(modelDir.path, '.complete'))
      .writeAsString(DateTime.now().toIso8601String());
}
