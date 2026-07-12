import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/voice/model_architecture_detector.dart';

void main() {
  group('detectArchitecture', () {
    test('detects transducer from encoder/decoder/joiner files', () {
      final entries = [
        'model/encoder-epoch-99-avg-1.int8.onnx',
        'model/decoder-epoch-99-avg-1.int8.onnx',
        'model/joiner-epoch-99-avg-1.int8.onnx',
        'model/tokens.txt',
      ];
      expect(detectArchitecture(entries), ModelArchitecture.transducer);
    });

    test('detects kokoro from voices.bin', () {
      final entries = [
        'kokoro/model.onnx',
        'kokoro/voices.bin',
        'kokoro/tokens.txt',
      ];
      expect(detectArchitecture(entries), ModelArchitecture.kokoro);
    });

    test('detects vitsPiper from espeak-ng-data directory', () {
      final entries = [
        'piper/model.onnx',
        'piper/tokens.txt',
        'piper/espeak-ng-data/en-us_dict',
      ];
      expect(detectArchitecture(entries), ModelArchitecture.vitsPiper);
    });

    test('detects ctc from model.onnx and tokens.txt without espeak', () {
      final entries = [
        'ctc/model.onnx',
        'ctc/tokens.txt',
      ];
      expect(detectArchitecture(entries), ModelArchitecture.ctc);
    });

    test('returns null when no pattern matches', () {
      final entries = [
        'unknown/weights.bin',
        'unknown/config.json',
      ];
      expect(detectArchitecture(entries), isNull);
    });

    test('detects transducer for encoder+decoder+joiner regardless of naming style', () {
      final entries = [
        'nemo/encoder-epoch-30-avg-1.onnx',
        'nemo/decoder-epoch-30-avg-1.onnx',
        'nemo/joiner-epoch-30-avg-1.onnx',
        'nemo/tokens.txt',
      ];
      // Both Zipformer and NeMo transducers map to transducer
      expect(detectArchitecture(entries), ModelArchitecture.transducer);
    });
  });
}
