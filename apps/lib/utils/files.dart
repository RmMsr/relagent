// Contains code from sherpa-onnx. Copyright (c) 2024  Xiaomi Corporation
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'logger.dart';

/// Copies a bundled asset into the cache directory and returns its path.
///
/// Native only — callers reach this through the sherpa voice services, which
/// web replaces with no-ops.
Future<String> copyAssetFileToCache(String src, [String? dst]) async {
  if (kIsWeb) {
    throw UnsupportedError('Caching asset $src requires local storage');
  }
  final Directory directory = await getApplicationCacheDirectory();
  final target = join(directory.path, src);
  final targetFile = File(target);
  bool exists = await targetFile.exists();

  // If file already exists in cache, verify it's complete
  if (exists) {
    final actualSize = await targetFile.length();
    Logger.debug('Cached file $src exists: $actualSize bytes at $target');

    // File must be non-zero size to be valid
    if (actualSize > 0) {
      // Try to verify size matches asset (only works in main isolate)
      try {
        final data = await rootBundle.load('assets/$src');
        final expectedSize = data.lengthInBytes;

        if (actualSize == expectedSize) {
          // File is complete and valid
          Logger.debug('✓ Cached file $src verified ($actualSize bytes)');
          return target;
        } else {
          Logger.debug(
            '✗ Cached file $src is incomplete ($actualSize bytes vs $expectedSize expected), re-copying...',
          );
          // File is corrupted or incomplete, will re-copy below
        }
      } catch (e) {
        // Can't access rootBundle (likely background isolate)
        // Assume file is OK if it's non-zero size
        Logger.debug(
          '✓ Cached file $src (background isolate, size: $actualSize bytes)',
        );
        return target;
      }
    } else {
      Logger.debug('✗ Cached file $src is empty (0 bytes), re-copying...');
      // File is empty, will re-copy below
    }
  }

  // File doesn't exist or is corrupted, need to copy from assets (requires main isolate)
  final data = await rootBundle.load('assets/$src');

  final parentDir = targetFile.parent;
  if (!await parentDir.exists()) {
    await parentDir.create(recursive: true);
  }

  final List<int> bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );

  await targetFile.writeAsBytes(bytes);

  return target;
}

/// Writes 16-bit PCM mono [samples] to a WAV file under
/// `<cache>/debug_audio/`, for pulling real on-device audio (e.g. VAD
/// segments fed to an ASR recognizer) into offline test harnesses like
/// `experiments/nb-whisper-onnx/sanity_check.py`.
///
/// A no-op returning null unless built with
/// `--dart-define=debug_logs_enabled=true` — this is diagnostic-only and
/// must never run in normal use.
Future<String?> dumpDebugWav(
  String filename,
  Float32List samples,
  int sampleRate,
) async {
  if (!Logger.debugLogsEnabled || kIsWeb) return null;

  final directory = await getApplicationCacheDirectory();
  final target = join(directory.path, 'debug_audio', filename);
  final targetFile = File(target);
  await targetFile.parent.create(recursive: true);

  final pcm = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    pcm[i] = (samples[i].clamp(-1.0, 1.0) * 32767).round();
  }
  final dataBytes = pcm.buffer.asUint8List();

  final header = BytesBuilder()
    ..add('RIFF'.codeUnits)
    ..add(_uint32le(36 + dataBytes.length))
    ..add('WAVE'.codeUnits)
    ..add('fmt '.codeUnits)
    ..add(_uint32le(16))
    ..add(_uint16le(1)) // PCM
    ..add(_uint16le(1)) // mono
    ..add(_uint32le(sampleRate))
    ..add(_uint32le(sampleRate * 2)) // byte rate, 16-bit mono
    ..add(_uint16le(2)) // block align
    ..add(_uint16le(16)) // bits per sample
    ..add('data'.codeUnits)
    ..add(_uint32le(dataBytes.length))
    ..add(dataBytes);

  await targetFile.writeAsBytes(header.toBytes());
  Logger.debug('[dumpDebugWav] Wrote ${dataBytes.length} bytes to $target');
  return target;
}

List<int> _uint32le(int v) =>
    [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

List<int> _uint16le(int v) => [v & 0xff, (v >> 8) & 0xff];

