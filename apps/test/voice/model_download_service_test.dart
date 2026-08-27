import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/voice/model_download_service.dart';

/// Redirects path_provider support + temp directories to a temp dir for tests.
class _FakeSupportPathProvider extends PathProviderPlatform {
  final String basePath;
  _FakeSupportPathProvider(this.basePath);

  @override
  Future<String?> getApplicationSupportPath() async => basePath;

  @override
  Future<String?> getTemporaryPath() async => basePath;
}

/// Simulates a platform that ships no path_provider implementation, as on web.
class _UnavailablePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException(
        'No implementation found for method getApplicationSupportDirectory '
        'on channel plugins.flutter.io/path_provider',
      );
}

void main() {
  setUpAll(() async {
    final fixture = await File(
      'test/fixtures/voice-models.json',
    ).readAsString();
    await ModelCatalog.init(jsonOverride: fixture);
  });

  group('ModelDownloadService — lifecycle', () {
    late Directory tempDir;
    late ModelDownloadService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('model_dl_test_');
      PathProviderPlatform.instance = _FakeSupportPathProvider(tempDir.path);
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

    // The startup scan is unawaited, so throwing here leaves the model UI
    // stuck on "scanning" and raises an uncaught async error.
    test('scanning degrades to empty without local storage', () async {
      PathProviderPlatform.instance = _UnavailablePathProvider();

      expect(await service.listDownloadedModels(), isEmpty);
      expect(await service.totalStorageUsed(), 0);
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

    test(
      'listDownloadedModels ignores directory without .complete marker',
      () async {
        // Simulate an interrupted download (directory exists, no marker)
        final modelDir = Directory(
          p.join(tempDir.path, 'models', 'asr', 'zipformer-en-kroko'),
        );
        await modelDir.create(recursive: true);
        await File(p.join(modelDir.path, 'encoder.onnx')).writeAsString('fake');

        final models = await service.listDownloadedModels();
        expect(models, isEmpty);
      },
    );

    test(
      'isModelDownloaded returns true when .complete marker exists',
      () async {
        await _seedFakeModel(tempDir, 'asr', 'zipformer-en-kroko');
        final result = await service.isModelDownloaded('zipformer-en-kroko');
        expect(result, isTrue);
      },
    );

    test(
      'listDownloadedModels finds models in both asr and tts subdirs',
      () async {
        await _seedFakeModel(tempDir, 'asr', 'zipformer-en-kroko');
        await _seedFakeModel(tempDir, 'tts', 'piper-en-lessac-medium-int8');

        final models = await service.listDownloadedModels();
        expect(
          models,
          containsAll(['zipformer-en-kroko', 'piper-en-lessac-medium-int8']),
        );
      },
    );

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
      await expectLater(service.deleteModel('non-existent-model'), completes);
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
      await File(
        p.join(modelDir.path, 'model.onnx'),
      ).writeAsBytes(List.filled(2048, 0));
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

    // --- interrupted downloads ---

    test('downloadModel throws when the connection drops mid-transfer '
        '(not silently treated as cancellation)', () async {
      // Simulates a real-world interrupted download: the server accepts the
      // request, starts sending the body, then the connection dies before
      // all bytes arrive. dart:io/package:http surfaces this as the same
      // http.ClientException type used for deliberate cancelDownload() —
      // the fix must tell the two apart instead of swallowing this as a
      // no-op "cancelled" (which leaves the caller believing nothing is
      // wrong while no model was ever saved).
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        // Write a raw response that promises far more bytes than it sends,
        // then gracefully close the socket (FIN, not RST). This is what
        // dart:io surfaces as HttpException("Connection closed while
        // receiving data"), which package:http's IOClient wraps as
        // http.ClientException — the same exception type raised for a
        // deliberate cancelDownload() call.
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'Content-Length: 1000000\r\n'
          'Connection: close\r\n'
          '\r\n',
        );
        socket.add(List.filled(1000, 0));
        await socket.flush();
        await socket.close();
      });

      final entry = CatalogEntry(
        id: 'interrupted-model',
        displayName: 'Interrupted Model',
        type: ModelType.asr,
        languages: const ['en'],
        architecture: ModelArchitecture.transducer,
        downloadUrl:
            'http://${server.address.host}:${server.port}/model.tar.bz2',
        downloadSizeMb: 1,
        fileStructure: const {},
        origin: 'test',
        sourceUrl: 'http://example.invalid',
        releaseDate: '2025-01',
      );

      await expectLater(service.downloadModel(entry), throwsA(anything));

      // Nothing should be reported as downloaded after a dropped connection.
      // (isModelDownloaded() would trivially return false here regardless,
      // since this ad-hoc entry isn't registered in ModelCatalog — check the
      // actual extracted directory instead.)
      final modelDir = Directory(
        p.join(tempDir.path, 'models', 'asr', 'interrupted-model'),
      );
      expect(await modelDir.exists(), isFalse);

      // The partial bytes must survive the failure — deleting them would
      // force every retry to redownload the whole (possibly huge) archive
      // from scratch instead of resuming.
      final partialFile = File(
        p.join(tempDir.path, 'interrupted-model.tar.bz2'),
      );
      expect(partialFile.existsSync(), isTrue);
      expect(partialFile.lengthSync(), 1000);
    });

    test('cancelDownload() still stops the download silently, without '
        'surfacing an error', () async {
      // A deliberate cancelDownload() call closes the same http.Client and
      // therefore raises the same http.ClientException as the dropped
      // connection above. This must stay a silent no-op, not an error.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.headers.contentLength = 1000000;
        // Drip-feed slowly so the test has time to call cancelDownload()
        // while the transfer is still in flight.
        for (var i = 0; i < 1000; i++) {
          request.response.add([0]);
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await request.response.close();
      });

      final entry = CatalogEntry(
        id: 'cancelled-model',
        displayName: 'Cancelled Model',
        type: ModelType.asr,
        languages: const ['en'],
        architecture: ModelArchitecture.transducer,
        downloadUrl:
            'http://${server.address.host}:${server.port}/model.tar.bz2',
        downloadSizeMb: 1,
        fileStructure: const {},
        origin: 'test',
        sourceUrl: 'http://example.invalid',
        releaseDate: '2025-01',
      );

      final future = service.downloadModel(entry);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      service.cancelDownload('cancelled-model');

      await expectLater(future, completes);
      final modelDir = Directory(
        p.join(tempDir.path, 'models', 'asr', 'cancelled-model'),
      );
      expect(await modelDir.exists(), isFalse);
    });

    // --- resuming downloads ---

    test(
      'downloadModel resumes from a partial file with a Range request',
      () async {
        final archiveBytes = _buildArchiveBytes({
          'resume-model/tokens.txt': [1, 2, 3],
          'resume-model/encoder.onnx': List.generate(4000, (i) => i % 256),
        });
        final splitPoint = (archiveBytes.length * 0.4).round();
        final alreadyDownloaded = archiveBytes.sublist(0, splitPoint);
        final remaining = archiveBytes.sublist(splitPoint);

        // Seed a prior, interrupted attempt in the temp dir under the exact
        // name _download() uses: '<modelId>.tar.bz2'.
        final partialFile = File(p.join(tempDir.path, 'resume-model.tar.bz2'));
        await partialFile.writeAsBytes(alreadyDownloaded);

        String? rangeHeaderSeen;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          rangeHeaderSeen = request.headers.value('range');
          request.response
            ..statusCode = 206
            ..headers.set(
              'Content-Range',
              'bytes $splitPoint-${archiveBytes.length - 1}/${archiveBytes.length}',
            )
            ..headers.contentLength = remaining.length
            ..add(remaining);
          await request.response.close();
        });

        final entry = CatalogEntry(
          id: 'resume-model',
          displayName: 'Resume Model',
          type: ModelType.asr,
          languages: const ['en'],
          architecture: ModelArchitecture.transducer,
          downloadUrl:
              'http://${server.address.host}:${server.port}/model.tar.bz2',
          downloadSizeMb: 1,
          fileStructure: const {},
          origin: 'test',
          sourceUrl: 'http://example.invalid',
          releaseDate: '2025-01',
        );

        final progressEvents = <DownloadProgress>[];
        await service.downloadModel(entry, onProgress: progressEvents.add);

        expect(rangeHeaderSeen, 'bytes=$splitPoint-');

        final modelDir = Directory(
          p.join(tempDir.path, 'models', 'asr', 'resume-model'),
        );
        expect(File(p.join(modelDir.path, '.complete')).existsSync(), isTrue);

        // Progress must account for the bytes we already had, not restart
        // from zero — otherwise the UI misleadingly resets to 0% on resume.
        expect(progressEvents, isNotEmpty);
        expect(
          progressEvents.first.bytesReceived,
          greaterThanOrEqualTo(splitPoint),
        );
        expect(progressEvents.last.bytesReceived, archiveBytes.length);

        expect(
          await File(p.join(modelDir.path, 'encoder.onnx')).readAsBytes(),
          List.generate(4000, (i) => i % 256),
        );
      },
    );

    test('downloadModel restarts from scratch when the server ignores the '
        'Range request', () async {
      final archiveBytes = _buildArchiveBytes({
        'restart-model/tokens.txt': [9, 9, 9],
      });

      // A stale/unrelated partial sitting in the temp dir — the server below
      // won't honor resuming it, so it must be discarded, not appended to.
      final partialFile = File(p.join(tempDir.path, 'restart-model.tar.bz2'));
      await partialFile.writeAsBytes(List.filled(500, 0xFF));

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        // Ignore any Range header and always send the full archive with 200,
        // like a server/CDN that doesn't support partial content.
        request.response
          ..statusCode = 200
          ..headers.contentLength = archiveBytes.length
          ..add(archiveBytes);
        await request.response.close();
      });

      final entry = CatalogEntry(
        id: 'restart-model',
        displayName: 'Restart Model',
        type: ModelType.asr,
        languages: const ['en'],
        architecture: ModelArchitecture.transducer,
        downloadUrl:
            'http://${server.address.host}:${server.port}/model.tar.bz2',
        downloadSizeMb: 1,
        fileStructure: const {},
        origin: 'test',
        sourceUrl: 'http://example.invalid',
        releaseDate: '2025-01',
      );

      await service.downloadModel(entry);

      final modelDir = Directory(
        p.join(tempDir.path, 'models', 'asr', 'restart-model'),
      );
      expect(File(p.join(modelDir.path, '.complete')).existsSync(), isTrue);
      expect(await File(p.join(modelDir.path, 'tokens.txt')).readAsBytes(), [
        9,
        9,
        9,
      ]);
    });
  });
}

/// Builds a valid tar.bz2 archive (matching what sherpa-onnx model releases
/// look like) from a map of {path: content}.
List<int> _buildArchiveBytes(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final tar = TarEncoder().encode(archive);
  return BZip2Encoder().encode(tar);
}

/// Creates a fake extracted model directory with a .complete marker.
Future<void> _seedFakeModel(
  Directory tempDir,
  String typeDir,
  String modelId,
) async {
  final modelDir = Directory(p.join(tempDir.path, 'models', typeDir, modelId));
  await modelDir.create(recursive: true);
  await File(
    p.join(modelDir.path, '.complete'),
  ).writeAsString(DateTime.now().toIso8601String());
}
