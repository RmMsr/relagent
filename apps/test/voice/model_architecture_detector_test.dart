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
      final entries = ['ctc/model.onnx', 'ctc/tokens.txt'];
      expect(detectArchitecture(entries), ModelArchitecture.ctc);
    });

    test('returns null when no pattern matches', () {
      final entries = ['unknown/weights.bin', 'unknown/config.json'];
      expect(detectArchitecture(entries), isNull);
    });

    test(
      'detects transducer for encoder+decoder+joiner regardless of naming style',
      () {
        final entries = [
          'model/encoder-epoch-30-avg-1.onnx',
          'model/decoder-epoch-30-avg-1.onnx',
          'model/joiner-epoch-30-avg-1.onnx',
          'model/tokens.txt',
        ];
        expect(detectArchitecture(entries), ModelArchitecture.transducer);
      },
    );

    test('guesses offlineNemoTransducer for encoder+decoder+joiner when '
        '"nemo" appears in the path', () {
      final entries = [
        'nemo/encoder-epoch-30-avg-1.onnx',
        'nemo/decoder-epoch-30-avg-1.onnx',
        'nemo/joiner-epoch-30-avg-1.onnx',
        'nemo/tokens.txt',
      ];
      // A guess only — the shape is ambiguous either way, see
      // isAmbiguousTransducerShape below.
      expect(
        detectArchitecture(entries),
        ModelArchitecture.offlineNemoTransducer,
      );
    });

    test(
      'detects whisper from sherpa-onnx export-onnx.py prefixed filenames',
      () {
        final entries = [
          'model/nb-whisper-base-encoder.onnx',
          'model/nb-whisper-base-decoder.onnx',
          'model/nb-whisper-base-tokens.txt',
        ];
        expect(detectArchitecture(entries), ModelArchitecture.whisper);
      },
    );

    test('detects whisper from int8-quantized prefixed filenames', () {
      final entries = [
        'model/nb-whisper-base-encoder.int8.onnx',
        'model/nb-whisper-base-decoder.int8.fp16emb.onnx',
        'model/nb-whisper-base-tokens.txt',
      ];
      expect(detectArchitecture(entries), ModelArchitecture.whisper);
    });

    test('detects whisper from bare (unprefixed) filenames', () {
      final entries = [
        'model/encoder.onnx',
        'model/decoder.onnx',
        'model/tokens.txt',
      ];
      expect(detectArchitecture(entries), ModelArchitecture.whisper);
    });

    test('does not detect whisper when a joiner file is present', () {
      // No other branch matches this shape either (prefixed names aren't
      // recognized by the bare-name transducer/CTC checks), so this
      // correctly falls through to unrecognized rather than misdetecting.
      final entries = [
        'model/nb-whisper-base-encoder.onnx',
        'model/nb-whisper-base-decoder.onnx',
        'model/nb-whisper-base-joiner.onnx',
        'model/nb-whisper-base-tokens.txt',
      ];
      expect(detectArchitecture(entries), isNull);
    });

    test('falls back to ctc (not whisper) when the tokens file does not '
        'match the encoder/decoder prefix', () {
      // A bare "tokens.txt" alongside prefixed encoder/decoder files still
      // satisfies the pre-existing hasModel+hasTokens CTC check, since
      // neither onnx file starts with the literal "encoder"/"decoder" the
      // CTC/transducer checks look for.
      final entries = [
        'model/nb-whisper-base-encoder.onnx',
        'model/nb-whisper-base-decoder.onnx',
        'model/tokens.txt',
      ];
      expect(detectArchitecture(entries), ModelArchitecture.ctc);
    });

    test('still detects a legit transducer shape unaffected by the whisper '
        'branch (regression)', () {
      final entries = [
        'model/encoder-epoch-99-avg-1.int8.onnx',
        'model/decoder-epoch-99-avg-1.int8.onnx',
        'model/joiner-epoch-99-avg-1.int8.onnx',
        'model/tokens.txt',
      ];
      expect(detectArchitecture(entries), ModelArchitecture.transducer);
    });

    test('still detects ctc unaffected by the whisper branch (regression)', () {
      final entries = ['ctc/model.onnx', 'ctc/tokens.txt'];
      expect(detectArchitecture(entries), ModelArchitecture.ctc);
    });
  });

  group('isAmbiguousTransducerShape', () {
    test('true for encoder+decoder+joiner, with or without "nemo" in path', () {
      expect(
        isAmbiguousTransducerShape([
          'model/encoder.onnx',
          'model/decoder.onnx',
          'model/joiner.onnx',
          'model/tokens.txt',
        ]),
        isTrue,
      );
      expect(
        isAmbiguousTransducerShape([
          'nemo/encoder.onnx',
          'nemo/decoder.onnx',
          'nemo/joiner.onnx',
          'nemo/tokens.txt',
        ]),
        isTrue,
      );
    });

    test('false for shapes that are not encoder+decoder+joiner', () {
      expect(
        isAmbiguousTransducerShape(['ctc/model.onnx', 'ctc/tokens.txt']),
        isFalse,
      );
      expect(isAmbiguousTransducerShape(['kokoro/voices.bin']), isFalse);
    });
  });
}
