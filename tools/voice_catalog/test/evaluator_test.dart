import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:voice_catalog/evaluator.dart';

void main() {
  group('VoiceCatalogEvaluator.inspectDirectory', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('voice_catalog_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('detects tokens.txt with a shared model-name prefix (Whisper)', () async {
      // sherpa-onnx's whisper export-onnx.py names every file with a shared
      // "{model-name}-" prefix instead of the bare names every other
      // architecture uses. Regression test for the null-check crash this
      // caused: files['tokens']! on a Map that never got a 'tokens' entry.
      File(p.join(tempDir.path, 'nb-whisper-base-encoder.onnx')).createSync();
      File(p.join(tempDir.path, 'nb-whisper-base-decoder.onnx')).createSync();
      File(p.join(tempDir.path, 'nb-whisper-base-tokens.txt')).createSync();

      final structure = await VoiceCatalogEvaluator.inspectDirectory(tempDir.path);

      expect(structure['encoder'], 'nb-whisper-base-encoder.onnx');
      expect(structure['decoder'], 'nb-whisper-base-decoder.onnx');
      expect(structure['tokens'], 'nb-whisper-base-tokens.txt');
    });

    test('detects bare-named files (transducer/ctc/etc.)', () async {
      File(p.join(tempDir.path, 'encoder.onnx')).createSync();
      File(p.join(tempDir.path, 'decoder.onnx')).createSync();
      File(p.join(tempDir.path, 'joiner.onnx')).createSync();
      File(p.join(tempDir.path, 'tokens.txt')).createSync();

      final structure = await VoiceCatalogEvaluator.inspectDirectory(tempDir.path);

      expect(structure['encoder'], 'encoder.onnx');
      expect(structure['decoder'], 'decoder.onnx');
      expect(structure['joiner'], 'joiner.onnx');
      expect(structure['tokens'], 'tokens.txt');
    });

    test('does not mistake token-scores.json for tokens.txt', () async {
      File(p.join(tempDir.path, 'model.onnx')).createSync();
      File(p.join(tempDir.path, 'token-scores.json')).createSync();

      final structure = await VoiceCatalogEvaluator.inspectDirectory(tempDir.path);

      expect(structure['tokens'], isNull);
      expect(structure['tokenScoresJson'], 'token-scores.json');
    });
  });
}
