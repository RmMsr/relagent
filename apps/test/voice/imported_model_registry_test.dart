import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:relagent/models/imported_model.dart';
import 'package:relagent/voice/imported_model_registry.dart';

// ─── Fake path provider ───────────────────────────────────────────────────────

class _FakePathProvider
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;

  @override
  Future<String?> getApplicationCachePath() async => tempDir;

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

/// Simulates a platform that ships no path_provider implementation, as on web.
class _UnavailablePathProvider extends _FakePathProvider {
  _UnavailablePathProvider() : super('');

  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException(
        'No implementation found for method getApplicationSupportDirectory '
        'on channel plugins.flutter.io/path_provider',
      );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

ImportedModelEntry makeEntry({
  String id = 'imported-test01',
  String displayName = 'Test Model',
  ModelType type = ModelType.asr,
  ModelArchitecture architecture = ModelArchitecture.transducer,
  List<String> languages = const ['en'],
  DateTime? importedAt,
}) {
  return ImportedModelEntry(
    id: id,
    displayName: displayName,
    type: type,
    architecture: architecture,
    languages: languages,
    importedAt: importedAt ?? DateTime(2026, 1, 1),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('registry_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('init with no manifest yields empty list', () async {
    await ImportedModelRegistry.init();
    expect(ImportedModelRegistry.entries, isEmpty);
  });

  // init() runs before runApp(); throwing here leaves the app on a blank screen.
  test(
    'init without path_provider yields empty list instead of throwing',
    () async {
      await ImportedModelRegistry.init();
      await ImportedModelRegistry.add(makeEntry());

      PathProviderPlatform.instance = _UnavailablePathProvider();

      await expectLater(ImportedModelRegistry.init(), completes);
      expect(ImportedModelRegistry.entries, isEmpty);
    },
  );

  test('add persists entry and it appears in entries', () async {
    await ImportedModelRegistry.init();
    final e = makeEntry();
    await ImportedModelRegistry.add(e);

    expect(ImportedModelRegistry.entries, hasLength(1));
    expect(ImportedModelRegistry.entries.first.id, e.id);
  });

  test('manifest is reloaded correctly on next init', () async {
    await ImportedModelRegistry.init();
    await ImportedModelRegistry.add(makeEntry(id: 'imported-aaa'));
    await ImportedModelRegistry.add(makeEntry(id: 'imported-bbb'));

    await ImportedModelRegistry.init(); // reload from disk
    expect(ImportedModelRegistry.entries, hasLength(2));
  });

  test('remove deletes entry and updates manifest', () async {
    await ImportedModelRegistry.init();
    await ImportedModelRegistry.add(makeEntry(id: 'imported-aaa'));
    await ImportedModelRegistry.add(makeEntry(id: 'imported-bbb'));
    await ImportedModelRegistry.remove('imported-aaa');

    expect(ImportedModelRegistry.entries, hasLength(1));
    expect(ImportedModelRegistry.entries.first.id, 'imported-bbb');

    await ImportedModelRegistry.init();
    expect(ImportedModelRegistry.entries, hasLength(1));
  });

  test('findById returns correct entry or null', () async {
    await ImportedModelRegistry.init();
    await ImportedModelRegistry.add(makeEntry(id: 'imported-find01'));

    expect(ImportedModelRegistry.findById('imported-find01'), isNotNull);
    expect(ImportedModelRegistry.findById('imported-missing'), isNull);
  });

  test('byType returns only matching type, newest first', () async {
    await ImportedModelRegistry.init();
    await ImportedModelRegistry.add(
      makeEntry(
        id: 'imported-a1',
        type: ModelType.asr,
        importedAt: DateTime(2026, 1, 1),
      ),
    );
    await ImportedModelRegistry.add(
      makeEntry(
        id: 'imported-a2',
        type: ModelType.asr,
        importedAt: DateTime(2026, 1, 2),
      ),
    );
    await ImportedModelRegistry.add(
      makeEntry(id: 'imported-t1', type: ModelType.tts),
    );

    final asr = ImportedModelRegistry.byType(ModelType.asr);
    expect(asr, hasLength(2));
    expect(asr.first.id, 'imported-a2'); // newer first
    expect(ImportedModelRegistry.byType(ModelType.tts), hasLength(1));
  });
}
