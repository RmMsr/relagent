import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/tts/audio_source.dart';

/// Minimal 16-bit mono PCM WAV matching generateWavBytes' header layout.
Uint8List _wav({
  int sampleRate = 16000,
  int numChannels = 1,
  int bitsPerSample = 16,
  int dataBytes = 8,
}) {
  final fileSize = 44 + dataBytes;
  final buffer = ByteData(fileSize);
  buffer.setUint8(0, 0x52);
  buffer.setUint8(1, 0x49);
  buffer.setUint8(2, 0x46);
  buffer.setUint8(3, 0x46);
  buffer.setUint32(4, fileSize - 8, Endian.little);
  buffer.setUint8(8, 0x57);
  buffer.setUint8(9, 0x41);
  buffer.setUint8(10, 0x56);
  buffer.setUint8(11, 0x45);
  buffer.setUint8(12, 0x66);
  buffer.setUint8(13, 0x6D);
  buffer.setUint8(14, 0x74);
  buffer.setUint8(15, 0x20);
  buffer.setUint32(16, 16, Endian.little);
  buffer.setUint16(20, 1, Endian.little);
  buffer.setUint16(22, numChannels, Endian.little);
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(
    28,
    sampleRate * numChannels * bitsPerSample ~/ 8,
    Endian.little,
  );
  buffer.setUint16(32, numChannels * bitsPerSample ~/ 8, Endian.little);
  buffer.setUint16(34, bitsPerSample, Endian.little);
  buffer.setUint8(36, 0x64);
  buffer.setUint8(37, 0x61);
  buffer.setUint8(38, 0x74);
  buffer.setUint8(39, 0x61);
  buffer.setUint32(40, dataBytes, Endian.little);
  final bytes = buffer.buffer.asUint8List();
  for (var i = 0; i < dataBytes; i++) {
    bytes[44 + i] = 0xAB;
  }
  return bytes;
}

void main() {
  group('appendSilenceToWav', () {
    test('extends the file and data-size header fields', () {
      final original = _wav(sampleRate: 16000, numChannels: 1, bitsPerSample: 16);
      final result = appendSilenceToWav(original, const Duration(milliseconds: 100));

      // 16000 Hz * 0.1s * 1 channel * 2 bytes/sample = 3200 bytes of silence.
      expect(result.length, original.length + 3200);

      final header = ByteData.sublistView(result, 0, 44);
      expect(header.getUint32(4, Endian.little), result.length - 8);
      expect(header.getUint32(40, Endian.little), 8 + 3200);
    });

    test('appended bytes are silent (zero)', () {
      final original = _wav(dataBytes: 4);
      final result = appendSilenceToWav(original, const Duration(milliseconds: 50));

      final appended = result.sublist(original.length);
      expect(appended.every((b) => b == 0), isTrue);
      // Original audio bytes are untouched.
      expect(result.sublist(44, 44 + 4), original.sublist(44, 44 + 4));
    });

    test('zero duration returns the input unchanged', () {
      final original = _wav();
      final result = appendSilenceToWav(original, Duration.zero);
      expect(result, same(original));
    });

    test('input shorter than a WAV header is returned unchanged', () {
      final tooShort = Uint8List(10);
      final result = appendSilenceToWav(tooShort, const Duration(milliseconds: 100));
      expect(result, same(tooShort));
    });
  });
}
