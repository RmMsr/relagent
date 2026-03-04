// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/models/model_catalog.dart';
import '/speech_recognition/asr_metadata.dart';
import '/speech_recognition/sherpa_streaming_asr.dart';
import '/tts/sherpa_tts.dart';
import '/voice/download_model_loader.dart';
import '/voice/model_download_service.dart';
import 'catalog_index.dart';

/// Downloads and smoke-tests untested voice model entries that pass the filter.
///
/// After each entry completes (pass or fail), writes the updated JSON to disk
/// for crash resilience. The developer reviews the notes and promotes passing
/// entries to `approved`.
class VoiceCatalogEvaluator {
  final CatalogIndex index;
  final String fixtureDir;

  VoiceCatalogEvaluator({required this.index, required this.fixtureDir});

  /// Evaluate all untested entries without an exclusion note.
  Future<List<Map<String, dynamic>>> evaluate(
    List<Map<String, dynamic>> entries,
  ) async {
    final candidates = entries
        .where((e) => e['status'] == 'untested')
        .where((e) => !(e['notes'] as String? ?? '').startsWith('excluded:'))
        .toList();

    print('[Evaluate] ${candidates.length} entries to evaluate');

    var evaluated = 0;
    for (final entry in candidates) {
      final id = entry['id'] as String;
      print('[Evaluate] Testing $id...');
      await _evaluateEntry(entry);
      final note = entry['notes'] as String? ?? '';
      entry['status'] = note.startsWith('error:') ? 'failed' : 'evaluated';
      evaluated++;

      // Write after each entry for crash resilience.
      await index.save(entries);
      print('[Evaluate] [$evaluated/${candidates.length}] $id done');
    }

    return entries;
  }

  Future<void> _evaluateEntry(Map<String, dynamic> entry) async {
    try {
      final catalogEntry = _toCatalogEntry(entry);
      final service = ModelDownloadService();

      // Skip if already downloaded.
      final modelPath = await service.getModelPath(catalogEntry);
      final marker = File(p.join(modelPath, '.complete'));
      if (!await marker.exists()) {
        print('[Evaluate] Downloading ${catalogEntry.id}...');
        await service.downloadModel(
          catalogEntry,
          onProgress: (p) {
            if (p.totalBytes > 0 && p.percent % 20 == 0) {
              stdout.write('\r  ${p.percent}%');
            }
          },
        );
        stdout.writeln();
      } else {
        print('[Evaluate] Already downloaded, skipping download');
      }

      // Inspect archive contents and populate fileStructure.
      final fileStructure = await _inspectModelDirectory(modelPath);
      entry['fileStructure'] = fileStructure;

      // Run inference smoke-test.
      final type = entry['type'] as String;
      final stopwatch = Stopwatch()..start();

      if (type == 'asr') {
        await _evaluateAsr(catalogEntry, entry);
      } else {
        await _evaluateTts(catalogEntry, entry);
      }

      stopwatch.stop();
      final existingNotes = entry['notes'] as String? ?? '';
      final latencyNote = 'latency: ${stopwatch.elapsedMilliseconds}ms';
      entry['notes'] =
          existingNotes.isEmpty ? latencyNote : '$existingNotes; $latencyNote';
    } catch (e) {
      final existing = entry['notes'] as String? ?? '';
      entry['notes'] = existing.isEmpty ? 'error: $e' : '$existing; error: $e';
      print('[Evaluate] Error: $e');
    }
  }

  Future<void> _evaluateAsr(
    CatalogEntry entry,
    Map<String, dynamic> rawEntry,
  ) async {
    final loader = DownloadModelLoader(entry);
    final metadata = AsrModelMetadata(
      architecture: entry.architecture,
      fileStructure: entry.fileStructure.isNotEmpty
          ? entry.fileStructure
          : _guessFileStructure(entry.architecture),
      loader: loader,
      modelId: entry.id,
    );

    final langs = (rawEntry['languages'] as List<dynamic>? ?? []).cast<String>();
    final primaryLang = langs.isNotEmpty ? langs.first : 'en';
    final wavPath = _fixturePath(primaryLang);

    sherpa_onnx.OnlineRecognizer? recognizer;
    try {
      recognizer = await createOnlineRecognizerFromMetadata(metadata);
      final stream = recognizer.createStream();

      final wavData = await _readWavSamples(wavPath);
      stream.acceptWaveform(samples: wavData, sampleRate: 16000);
      recognizer.decode(stream);
      final result = recognizer.getResult(stream).text;
      stream.free();

      if (result.isEmpty) {
        final existing = rawEntry['notes'] as String? ?? '';
        rawEntry['notes'] = existing.isEmpty
            ? 'note: inference produced empty output'
            : '$existing; note: inference produced empty output';
      }
    } finally {
      recognizer?.free();
    }
  }

  Future<void> _evaluateTts(
    CatalogEntry entry,
    Map<String, dynamic> rawEntry,
  ) async {
    final loader = DownloadModelLoader(entry);
    final metadata = TtsModelMetadata(
      architecture: entry.architecture,
      fileStructure: entry.fileStructure.isNotEmpty
          ? entry.fileStructure
          : _guessFileStructure(entry.architecture),
      loader: loader,
      modelId: entry.id,
    );

    sherpa_onnx.OfflineTts? tts;
    try {
      tts = await createOfflineTtsFromMetadata(metadata);
      final audio = tts.generate(
        text: 'Hello, this is a test.',
        sid: 0,
        speed: 1.0,
      );
      if (audio.samples.isEmpty) {
        final existing = rawEntry['notes'] as String? ?? '';
        rawEntry['notes'] = existing.isEmpty
            ? 'note: inference produced empty audio'
            : '$existing; note: inference produced empty audio';
      }
    } finally {
      tts?.free();
    }
  }

  /// Inspect the extracted model directory and return a fileStructure map.
  Future<Map<String, String>> _inspectModelDirectory(
    String modelPath,
  ) async {
    final dir = Directory(modelPath);
    if (!await dir.exists()) return {};

    final structure = <String, String>{};
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: modelPath);
      final name = p.basename(rel);

      if (name.endsWith('.onnx') && rel.contains('encoder')) {
        structure['encoder'] = rel;
      } else if (name.endsWith('.onnx') && rel.contains('decoder')) {
        structure['decoder'] = rel;
      } else if (name.endsWith('.onnx') && rel.contains('joiner')) {
        structure['joiner'] = rel;
      } else if (name.endsWith('.onnx') && rel.contains('model')) {
        structure['model'] = rel;
      } else if (name == 'tokens.txt') {
        structure['tokens'] = rel;
      } else if (name == 'voices.bin') {
        structure['voices'] = rel;
      }
    }

    // Check for espeak-ng-data directory.
    final dataDirPath = p.join(modelPath, 'espeak-ng-data');
    if (await Directory(dataDirPath).exists()) {
      structure['dataDir'] = 'espeak-ng-data';
    }

    return structure;
  }

  /// Make a best-guess fileStructure for known architectures.
  Map<String, String> _guessFileStructure(ModelArchitecture arch) {
    switch (arch) {
      case ModelArchitecture.transducer:
        return {
          'encoder': 'encoder.onnx',
          'decoder': 'decoder.onnx',
          'joiner': 'joiner.onnx',
          'tokens': 'tokens.txt',
        };
      case ModelArchitecture.offlineNemoTransducer:
        return {
          'encoder': 'encoder.int8.onnx',
          'decoder': 'decoder.int8.onnx',
          'joiner': 'joiner.int8.onnx',
          'tokens': 'tokens.txt',
        };
      case ModelArchitecture.kokoro:
        return {
          'model': 'model.int8.onnx',
          'voices': 'voices.bin',
          'tokens': 'tokens.txt',
          'dataDir': 'espeak-ng-data',
        };
      case ModelArchitecture.vitsPiper:
        return {'model': 'model.onnx', 'tokens': 'tokens.txt', 'dataDir': 'espeak-ng-data'};
      default:
        return {};
    }
  }

  String _fixturePath(String lang) {
    final langFile = File(p.join(fixtureDir, '$lang.wav'));
    if (langFile.existsSync()) return langFile.path;
    // Fall back to English.
    return p.join(fixtureDir, 'en.wav');
  }

  /// Read a 16 kHz mono WAV file and return samples as Float32List.
  Future<Float32List> _readWavSamples(String wavPath) async {
    final bytes = await File(wavPath).readAsBytes();
    // Skip 44-byte WAV header, read 16-bit PCM samples.
    const headerSize = 44;
    final count = (bytes.length - headerSize) ~/ 2;
    final samples = Float32List(count);
    for (var i = 0; i < count; i++) {
      final byteOffset = headerSize + i * 2;
      final raw = bytes[byteOffset] | (bytes[byteOffset + 1] << 8);
      final signed = raw > 32767 ? raw - 65536 : raw;
      samples[i] = signed / 32768.0;
    }
    return samples;
  }

  /// Convert a raw JSON entry to a [CatalogEntry] for use with services.
  CatalogEntry _toCatalogEntry(Map<String, dynamic> entry) {
    final typeStr = entry['type'] as String;
    final type =
        typeStr == 'asr' ? ModelType.asr : ModelType.tts;

    final archStr = entry['architecture'] as String;
    final architecture = ModelArchitecture.values.firstWhere(
      (e) => e.name == archStr,
      orElse: () => throw ArgumentError('Unknown architecture: $archStr'),
    );

    final fileStructureRaw =
        (entry['fileStructure'] as Map<dynamic, dynamic>? ?? {});
    final fileStructure = Map<String, String>.from(fileStructureRaw);

    return CatalogEntry(
      id: entry['id'] as String,
      displayName: entry['displayName'] as String? ?? entry['id'] as String,
      type: type,
      languages: List<String>.from(entry['languages'] as List? ?? []),
      architecture: architecture,
      downloadUrl: entry['downloadUrl'] as String,
      downloadSizeMb: (entry['downloadSizeMb'] as num).toDouble(),
      fileStructure: fileStructure,
      origin: entry['origin'] as String? ?? '',
      sourceUrl: entry['sourceUrl'] as String? ?? '',
      speakerCount: entry['speakerCount'] as int? ?? 0,
      releaseDate: entry['releaseDate'] as String? ?? '',
    );
  }
}

