import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:sherpa_voice/model_archive.dart';

/// Build a tar.bz2 archive from a map of {path: content}.
File _createArchive(String dir, Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final tar = TarEncoder().encode(archive);
  final bz2 = BZip2Encoder().encode(tar);
  final file = File(p.join(dir, 'test.tar.bz2'));
  file.writeAsBytesSync(bz2);
  return file;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sherpa_voice_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('extractModelArchive', () {
    test('strips common top-level directory prefix', () async {
      // Sherpa-onnx archives wrap all files in a model-named directory.
      // Extraction should strip that prefix so files land flat under destDir.
      final archive = _createArchive(tempDir.path, {
        'my-model-v1/tokens.txt': utf8.encode('hello'),
        'my-model-v1/encoder.onnx': [1, 2, 3, 4],
      });

      final dest = p.join(tempDir.path, 'out');
      await extractModelArchive(archive, dest);

      expect(File(p.join(dest, 'tokens.txt')).existsSync(), isTrue);
      expect(File(p.join(dest, 'encoder.onnx')).existsSync(), isTrue);
      expect(Directory(p.join(dest, 'my-model-v1')).existsSync(), isFalse);
    });

    test('preserves nested subdirectories', () async {
      // TTS models include deep directory trees like espeak-ng-data/lang/gmw/.
      final archive = _createArchive(tempDir.path, {
        'kokoro-v1/model.onnx': [1],
        'kokoro-v1/espeak-ng-data/lang/gmw/en': [2],
      });

      final dest = p.join(tempDir.path, 'out');
      await extractModelArchive(archive, dest);

      expect(
        File(p.join(dest, 'espeak-ng-data/lang/gmw/en')).existsSync(),
        isTrue,
      );
    });

    test('writes .complete marker after extraction', () async {
      final archive = _createArchive(tempDir.path, {
        'model/tokens.txt': utf8.encode('t'),
      });

      final dest = p.join(tempDir.path, 'out');
      await extractModelArchive(archive, dest);

      final marker = File(p.join(dest, '.complete'));
      expect(marker.existsSync(), isTrue);
      // Marker contains an ISO timestamp.
      expect(DateTime.tryParse(marker.readAsStringSync()), isNotNull);
    });

    test('keeps paths as-is when there is no common prefix', () async {
      final archive = _createArchive(tempDir.path, {
        'tokens.txt': utf8.encode('t'),
        'encoder.onnx': [1],
      });

      final dest = p.join(tempDir.path, 'out');
      await extractModelArchive(archive, dest);

      expect(File(p.join(dest, 'tokens.txt')).existsSync(), isTrue);
      expect(File(p.join(dest, 'encoder.onnx')).existsSync(), isTrue);
    });
  });
}
