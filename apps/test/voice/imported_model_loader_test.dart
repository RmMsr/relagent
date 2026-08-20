import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:relagent/models/imported_model.dart';
import 'package:relagent/voice/imported_model_loader.dart';

class _FakePathProvider
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String supportDir;
  _FakePathProvider(this.supportDir);

  @override
  Future<String?> getApplicationSupportPath() async => supportDir;

  @override
  Future<String?> getTemporaryPath() async => supportDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => supportDir;

  @override
  Future<String?> getApplicationCachePath() async => supportDir;

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
    tmpDir = await Directory.systemTemp.createTemp('loader_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  ImportedModelLoader _loader({
    String id = 'imported-abc12345',
    ModelType type = ModelType.asr,
  }) {
    return ImportedModelLoader(
      ImportedModelEntry(
        id: id,
        displayName: 'Test',
        type: type,
        architecture: ModelArchitecture.transducer,
        languages: [],
        importedAt: DateTime(2026),
      ),
    );
  }

  test(
    'isModelAvailable returns false when directory does not exist',
    () async {
      final loader = _loader();
      expect(await loader.isModelAvailable('test'), isFalse);
    },
  );

  test(
    'isModelAvailable returns false when .complete marker is absent',
    () async {
      final modelDir = Directory(
        p.join(tmpDir.path, 'imported_models', 'asr', 'imported-abc12345'),
      );
      await modelDir.create(recursive: true);

      final loader = _loader();
      expect(await loader.isModelAvailable('test'), isFalse);
    },
  );

  test('isModelAvailable returns true when .complete marker exists', () async {
    final modelDir = Directory(
      p.join(tmpDir.path, 'imported_models', 'asr', 'imported-abc12345'),
    );
    await modelDir.create(recursive: true);
    await File(p.join(modelDir.path, '.complete')).writeAsString('done');

    final loader = _loader();
    expect(await loader.isModelAvailable('test'), isTrue);
  });

  test(
    'loadModel returns path under support/imported_models/asr/<id>',
    () async {
      final loader = _loader(type: ModelType.asr);
      final path = await loader.loadModel('any');
      expect(path, contains('imported_models'));
      expect(path, contains('asr'));
      expect(path, contains('imported-abc12345'));
    },
  );

  test('loadModel uses tts subdir for tts models', () async {
    final loader = _loader(type: ModelType.tts);
    final path = await loader.loadModel('any');
    expect(path, contains('tts'));
  });
}
