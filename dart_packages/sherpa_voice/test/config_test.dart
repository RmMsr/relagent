import 'package:test/test.dart';

import 'package:sherpa_voice/asr_config.dart';
import 'package:sherpa_voice/model_architecture.dart';
import 'package:sherpa_voice/model_loader.dart';
import 'package:sherpa_voice/tts_config.dart';

/// Loader that returns dummy paths — sufficient for testing config assembly
/// logic without real model files.
class FakeModelLoader implements ModelLoader {
  final List<String> loadedFiles = [];

  @override
  Future<String> loadModel(String modelName) async => '/fake/$modelName';

  @override
  Future<String> loadModelFile(String modelName, String fileName) async {
    loadedFiles.add(fileName);
    return '/fake/$modelName/$fileName';
  }

  @override
  Future<String> loadModelDirectory(String modelName, String dirName) async {
    loadedFiles.add(dirName);
    return '/fake/$modelName/$dirName';
  }

  @override
  Future<bool> isModelAvailable(String modelName) async => true;
}

void main() {
  group('buildAsrRecognizer', () {
    test('rejects TTS-only architectures', () async {
      final loader = FakeModelLoader();
      // Kokoro is a TTS architecture — it must not be accepted for ASR.
      expect(
        () => buildAsrRecognizer(
          ModelArchitecture.kokoro,
          {'tokens': 'tokens.txt'},
          loader,
          'test-model',
        ),
        throwsArgumentError,
      );
    });

    test('rejects Piper VITS for ASR', () async {
      final loader = FakeModelLoader();
      expect(
        () => buildAsrRecognizer(
          ModelArchitecture.vitsPiper,
          {'tokens': 'tokens.txt'},
          loader,
          'test-model',
        ),
        throwsArgumentError,
      );
    });
  });

  group('buildTtsEngine', () {
    test('rejects ASR-only architectures', () async {
      final loader = FakeModelLoader();
      // Transducer is an ASR architecture — it must not be accepted for TTS.
      expect(
        () => buildTtsEngine(
          ModelArchitecture.transducer,
          {'tokens': 'tokens.txt'},
          loader,
          'test-model',
        ),
        throwsArgumentError,
      );
    });

    test('rejects CTC for TTS', () async {
      final loader = FakeModelLoader();
      expect(
        () => buildTtsEngine(
          ModelArchitecture.ctc,
          {'tokens': 'tokens.txt'},
          loader,
          'test-model',
        ),
        throwsArgumentError,
      );
    });
  });

  group('ModelArchitecture', () {
    test('covers all expected voice model types', () {
      // Guard against silently added enum values missing config support.
      expect(
        ModelArchitecture.values,
        containsAll([
          ModelArchitecture.transducer,
          ModelArchitecture.ctc,
          ModelArchitecture.onlineNemoCtc,
          ModelArchitecture.vitsPiper,
          ModelArchitecture.kokoro,
          ModelArchitecture.pocket,
        ]),
      );
    });
  });
}
