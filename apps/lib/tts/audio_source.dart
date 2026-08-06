import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// Custom audio source that plays audio from in-memory bytes
class InMemoryAudioSource extends StreamAudioSource {
  final Uint8List _bytes;

  InMemoryAudioSource(this._bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;

    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}

/// Appends [silence] worth of zero-amplitude PCM samples to a WAV file
/// produced by [generateWavBytes], patching the RIFF/data size fields to
/// match. Used to pace chunked TTS playback (e.g. a longer pause before a
/// heading) without needing SSML support from the synthesis engine.
Uint8List appendSilenceToWav(Uint8List wavBytes, Duration silence) {
  if (silence <= Duration.zero || wavBytes.length < 44) return wavBytes;

  final header = ByteData.sublistView(wavBytes, 0, 44);
  final sampleRate = header.getUint32(24, Endian.little);
  final numChannels = header.getUint16(22, Endian.little);
  final bitsPerSample = header.getUint16(34, Endian.little);
  final bytesPerFrame = numChannels * (bitsPerSample ~/ 8);

  final silenceFrames = (sampleRate * silence.inMicroseconds / 1000000).round();
  final silenceBytes = silenceFrames * bytesPerFrame;
  if (silenceBytes <= 0) return wavBytes;

  final result = Uint8List(wavBytes.length + silenceBytes);
  result.setRange(0, wavBytes.length, wavBytes);
  // Trailing bytes are already zero (silence) — Uint8List is zero-initialized.

  final resultHeader = ByteData.sublistView(result, 0, 44);
  final oldFileSize = header.getUint32(4, Endian.little);
  resultHeader.setUint32(4, oldFileSize + silenceBytes, Endian.little);
  final oldDataSize = header.getUint32(40, Endian.little);
  resultHeader.setUint32(40, oldDataSize + silenceBytes, Endian.little);

  return result;
}

/// Converts GeneratedAudio from Sherpa-ONNX to WAV bytes
Uint8List generateWavBytes(dynamic audio) {
  final samples = audio.samples;
  final sampleRate = audio.sampleRate;
  final numChannels = 1; // Mono
  final bitsPerSample = 16;

  // Convert float samples [-1, 1] to 16-bit PCM
  final pcmData = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    // Clamp to [-1, 1] and convert to 16-bit integer
    final sample = samples[i].clamp(-1.0, 1.0);
    pcmData[i] = (sample * 32767).round();
  }

  // Calculate sizes
  final dataSize = pcmData.lengthInBytes;
  final fileSize = 44 + dataSize; // 44 bytes for WAV header

  // Create WAV file in memory
  final buffer = ByteData(fileSize);

  // RIFF header
  buffer.setUint8(0, 0x52); // 'R'
  buffer.setUint8(1, 0x49); // 'I'
  buffer.setUint8(2, 0x46); // 'F'
  buffer.setUint8(3, 0x46); // 'F'
  buffer.setUint32(4, fileSize - 8, Endian.little); // File size - 8

  // WAVE format
  buffer.setUint8(8, 0x57); // 'W'
  buffer.setUint8(9, 0x41); // 'A'
  buffer.setUint8(10, 0x56); // 'V'
  buffer.setUint8(11, 0x45); // 'E'

  // fmt subchunk
  buffer.setUint8(12, 0x66); // 'f'
  buffer.setUint8(13, 0x6D); // 'm'
  buffer.setUint8(14, 0x74); // 't'
  buffer.setUint8(15, 0x20); // ' '
  buffer.setUint32(16, 16, Endian.little); // Subchunk1 size (16 for PCM)
  buffer.setUint16(20, 1, Endian.little); // Audio format (1 = PCM)
  buffer.setUint16(22, numChannels, Endian.little); // Number of channels
  buffer.setUint32(24, sampleRate, Endian.little); // Sample rate
  buffer.setUint32(
    28,
    sampleRate * numChannels * bitsPerSample ~/ 8,
    Endian.little,
  ); // Byte rate
  buffer.setUint16(
    32,
    numChannels * bitsPerSample ~/ 8,
    Endian.little,
  ); // Block align
  buffer.setUint16(34, bitsPerSample, Endian.little); // Bits per sample

  // data subchunk
  buffer.setUint8(36, 0x64); // 'd'
  buffer.setUint8(37, 0x61); // 'a'
  buffer.setUint8(38, 0x74); // 't'
  buffer.setUint8(39, 0x61); // 'a'
  buffer.setUint32(40, dataSize, Endian.little); // Data size

  // Copy PCM data
  final bytes = buffer.buffer.asUint8List();
  final pcmBytes = pcmData.buffer.asUint8List();
  bytes.setRange(44, fileSize, pcmBytes);

  return bytes;
}
