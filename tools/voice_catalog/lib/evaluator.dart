// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sherpa_voice/asr_config.dart';
import 'package:sherpa_voice/model_architecture.dart';
import 'package:sherpa_voice/model_loader.dart';
import 'package:sherpa_voice/tts_config.dart';

import 'catalog_index.dart';
import 'download_service.dart';

/// Resolves model files by joining a base directory with the relative path.
class _DirectoryModelLoader implements ModelLoader {
  final String _baseDir;
  _DirectoryModelLoader(this._baseDir);

  @override
  Future<String> loadModel(String modelName) async => _baseDir;

  @override
  Future<String> loadModelFile(String modelName, String fileName) async =>
      p.join(_baseDir, fileName);

  @override
  Future<String> loadModelDirectory(String modelName, String dirName) async =>
      p.join(_baseDir, dirName);

  @override
  Future<bool> isModelAvailable(String modelName) async =>
      Directory(_baseDir).existsSync();
}

/// Initialise the sherpa-onnx native bindings.
///
/// [libDir] should point to the directory containing `libsherpa-onnx-c-api.so`
/// (and `libonnxruntime.so`). When null the library is looked up via the
/// system linker (LD_LIBRARY_PATH must be set by the caller).
void initSherpaOnnx({String? libDir}) {
  // initBindings takes a directory path and appends the lib filename itself.
  // Pass null to fall back to LD_LIBRARY_PATH / system linker.
  sherpa_onnx.initBindings(libDir?.isNotEmpty == true ? libDir : null);
}

/// Downloads and smoke-tests untested model entries that pass the filter.
///
/// Downloaded model data is deleted after each test unless [keep] is true.
/// Writes the catalog JSON after each entry for crash resilience.
/// Pass [limitToIds] to evaluate only a specific subset of entries.
/// Pass [debug] to print stack traces and file inspection details.
class VoiceCatalogEvaluator {
  final CatalogIndex index;
  final ModelDownloadService downloader;
  final String fixtureDir;
  final bool keep;
  final bool debug;
  final Set<String>? limitToIds;
  final String? typeFilter;
  final Set<String> languages;

  /// Which entry status to target: 'pending', 'failed', or 'approved'.
  final String evalStatus;

  VoiceCatalogEvaluator({
    required this.index,
    required this.downloader,
    required this.fixtureDir,
    this.keep = false,
    this.debug = false,
    this.limitToIds,
    this.typeFilter,
    this.languages = const {},
    this.evalStatus = 'pending',
  });

  /// Evaluate entries matching [evalStatus] (or only [limitToIds] if set).
  Future<List<Map<String, dynamic>>> evaluate(
    List<Map<String, dynamic>> entries,
  ) async {
    final candidates = entries
        .where((e) {
          final status = e['status'] as String? ?? '';
          return switch (evalStatus) {
            'failed' => status == 'failed',
            'approved' => status == 'approved',
            _ => status == 'untested' &&
                !(e['notes'] as String? ?? '').startsWith('excluded:') &&
                !(e['notes'] as String? ?? '').startsWith('skipped:'),
          };
        })
        .where((e) =>
            limitToIds == null || limitToIds!.contains(e['id'] as String))
        .where((e) =>
            typeFilter == null || (e['type'] as String? ?? '') == typeFilter)
        .where((e) => _matchesLanguage(e))
        .toList();

    print('[Evaluate] ${candidates.length} entries to evaluate');
    if (!keep) {
      print('[Evaluate] Downloads will be deleted after each test (--keep to retain)');
    }

    var done = 0;
    for (final entry in candidates) {
      final id = entry['id'] as String;
      print('[Evaluate] [$done/${candidates.length}] Testing $id...');
      await _evaluateEntry(entry);
      final note = entry['notes'] as String? ?? '';
      entry['status'] = note.startsWith('error:') ? 'failed' : 'approved';
      done++;
      await index.save(entries);
      final logStatus = note.startsWith('error:') ? 'FAIL' : 'OK';
      print('[Evaluate] $logStatus — $id: $note');
    }

    return entries;
  }

  Future<void> _evaluateEntry(Map<String, dynamic> entry) async {
    // Reset so each evaluation run starts from a clean slate.
    entry['notes'] = '';
    entry['fileStructure'] = <String, String>{};

    final type = entry['type'] as String;
    final arch = entry['architecture'] as String;
    final id = entry['id'] as String;
    final downloadUrl = entry['downloadUrl'] as String;
    final typeDir = type == 'asr' ? 'asr' : 'tts';

    try {
      final modelDir = await downloader.downloadModel(
        typeDir,
        id,
        downloadUrl,
        onProgress: (recv, total) {
          if (total > 0) {
            final pct = (recv / total * 100).round();
            if (pct > 0 && pct % 25 == 0) stdout.write('\r  $pct%');
          }
        },
      );
      stdout.writeln();

      // Inspect directory and populate fileStructure.
      final fileStructure = await _inspectDirectory(modelDir);
      entry['fileStructure'] = fileStructure;

      // Auto-detect languages when none are known yet.
      final existingLangs =
          (entry['languages'] as List<dynamic>? ?? []).cast<String>();
      if (existingLangs.isEmpty) {
        final detected = await _detectLanguages(modelDir, fileStructure);
        if (detected.isNotEmpty) {
          entry['languages'] = detected;
          if (debug) stderr.writeln('[Debug] Detected languages: $detected');
        }
      }

      final stopwatch = Stopwatch()..start();

      if (type == 'asr') {
        await _evaluateAsr(id, arch, fileStructure, modelDir, entry);
      } else {
        await _evaluateTts(id, arch, fileStructure, modelDir, entry);
      }

      stopwatch.stop();
      _appendNote(entry, 'latency: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e, st) {
      _appendNote(entry, 'error: $e');
      if (debug) stderr.writeln('[Debug] Stack trace:\n$st');
    } finally {
      // Clean up downloaded model to free disk space, unless --keep is set.
      if (!keep) {
        await downloader.deleteModel(typeDir, id);
      }
    }
  }

  Future<void> _evaluateAsr(
    String id,
    String arch,
    Map<String, dynamic> fileStructure,
    String modelDir,
    Map<String, dynamic> entry,
  ) async {
    ModelArchitecture architecture;
    try {
      architecture = ModelArchitecture.values.byName(arch);
    } on ArgumentError {
      final detected = _detectAsrArchitecture(fileStructure);
      if (detected == null) {
        _appendNote(entry, 'error: unrecognized ASR file structure');
        return;
      }
      architecture = detected;
      entry['architecture'] = detected.name;
      if (debug) stderr.writeln('[Debug] Detected ASR arch: ${detected.name}');
    }

    final files = Map<String, String>.from(fileStructure.cast<String, String>());
    final loader = _DirectoryModelLoader(modelDir);

    if (debug) {
      stderr.writeln('[Debug] arch: $arch  dir: $modelDir');
      stderr.writeln('[Debug] files: $files');
    }

    final sherpa_onnx.OnlineRecognizer recognizer;
    try {
      recognizer = await buildAsrRecognizer(architecture, files, loader, id);
    } on ArgumentError catch (e) {
      _appendNote(entry, 'skipped: ${e.message}');
      if (debug) stderr.writeln('[Debug] ArgumentError: ${e.message}');
      return;
    }

    final langs = (entry['languages'] as List<dynamic>? ?? []).cast<String>();
    final primaryLang = langs.isNotEmpty ? langs.first : 'en';
    final wavPath = _fixturePath(primaryLang);
    final wavData = await _readWavSamples(wavPath);

    try {
      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: wavData, sampleRate: 16000);
      // Online models process audio in steps — drain until no more data.
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final result = recognizer.getResult(stream).text;
      stream.free();
      if (result.isEmpty) _appendNote(entry, 'note: empty ASR output');
    } finally {
      recognizer.free();
    }
  }

  Future<void> _evaluateTts(
    String id,
    String arch,
    Map<String, dynamic> fileStructure,
    String modelDir,
    Map<String, dynamic> entry,
  ) async {
    ModelArchitecture architecture;
    try {
      architecture = ModelArchitecture.values.byName(arch);
    } on ArgumentError {
      final detected = _detectTtsArchitecture(fileStructure);
      if (detected == null) {
        _appendNote(entry, 'error: unrecognized TTS file structure');
        return;
      }
      architecture = detected;
      entry['architecture'] = detected.name;
      if (debug) stderr.writeln('[Debug] Detected TTS arch: ${detected.name}');
    }

    final files = Map<String, String>.from(fileStructure.cast<String, String>());
    final loader = _DirectoryModelLoader(modelDir);

    if (debug) {
      stderr.writeln('[Debug] arch: $arch  dir: $modelDir');
      stderr.writeln('[Debug] files: $files');
    }

    final sherpa_onnx.OfflineTts tts;
    try {
      tts = await buildTtsEngine(architecture, files, loader, id);
    } on ArgumentError catch (e) {
      _appendNote(entry, 'skipped: ${e.message}');
      if (debug) stderr.writeln('[Debug] ArgumentError: ${e.message}');
      return;
    }

    try {
      final sherpa_onnx.GeneratedAudio audio;
      if (architecture == ModelArchitecture.pocket) {
        // Pocket TTS uses voice cloning: pass a fixture wav as reference audio.
        final refWav = await _readWavSamples(_fixturePath('en'));
        audio = tts.generateWithConfig(
          text: 'Hello, this is a test.',
          config: sherpa_onnx.OfflineTtsGenerationConfig(
            referenceAudio: refWav,
            referenceSampleRate: 16000,
          ),
        );
      } else {
        audio = tts.generate(text: 'Hello, this is a test.', sid: 0, speed: 1.0);
      }
      if (audio.samples.isEmpty) _appendNote(entry, 'note: empty TTS output');
    } finally {
      tts.free();
    }
  }

  /// Infer TTS architecture from the file structure detected by [_inspectDirectory].
  ///
  /// Returns null when the structure doesn't match any known pattern.
  ModelArchitecture? _detectTtsArchitecture(Map<String, dynamic> files) {
    if (files.containsKey('voices')) return ModelArchitecture.kokoro;
    if (files.containsKey('lmFlow') || files.containsKey('vocabJson')) {
      return ModelArchitecture.pocket;
    }
    if (files.containsKey('dataDir') && files.containsKey('model')) {
      return ModelArchitecture.vitsPiper;
    }
    return null;
  }

  /// Infer ASR architecture from the file structure detected by [_inspectDirectory].
  ///
  /// Returns null when the structure doesn't match any known pattern.
  ModelArchitecture? _detectAsrArchitecture(Map<String, dynamic> files) {
    if (files.containsKey('encoder') &&
        files.containsKey('decoder') &&
        files.containsKey('joiner')) {
      return ModelArchitecture.transducer;
    }
    if (files.containsKey('encoder') && files.containsKey('tokens')) {
      return ModelArchitecture.ctc;
    }
    return null;
  }

  Future<Map<String, dynamic>> _inspectDirectory(String modelDir) async {
    final dir = Directory(modelDir);
    if (!await dir.exists()) return {};

    final structure = <String, dynamic>{};
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: modelDir);
      final name = p.basename(rel);

      if (name.endsWith('.onnx') &&
          (rel.contains('lm_flow') || rel.contains('lm-flow'))) {
        structure['lmFlow'] = rel;
      } else if (name.endsWith('.onnx') &&
          (rel.contains('lm_main') || rel.contains('lm-main'))) {
        structure['lmMain'] = rel;
      } else if (name.endsWith('.onnx') &&
          (rel.contains('text_conditioner') ||
              rel.contains('text-conditioner'))) {
        structure['textConditioner'] = rel;
      } else if (name.endsWith('.onnx') && rel.contains('encoder')) {
        structure['encoder'] = rel;
      } else if (name.endsWith('.onnx') && rel.contains('decoder')) {
        structure['decoder'] = rel;
      } else if (name.endsWith('.onnx') && rel.contains('joiner')) {
        structure['joiner'] = rel;
      } else if (name.endsWith('.onnx') && rel.contains('model')) {
        structure['model'] = rel;
      } else if (name.endsWith('.onnx')) {
        // Piper VITS and similar models use an arbitrary filename (e.g.
        // da_DK-talesyntese-medium.onnx). Use as 'model' fallback.
        structure.putIfAbsent('model', () => rel);
      } else if (name == 'tokens.txt') {
        structure['tokens'] = rel;
      } else if (name == 'lang_list.txt' ||
          name == 'language_list.txt' ||
          name == 'languages.txt') {
        structure.putIfAbsent('langList', () => rel);
      } else if (name == 'voices.bin') {
        structure['voices'] = rel;
      } else if (name == 'vocab.json') {
        structure['vocabJson'] = rel;
      } else if (name == 'token-scores.json' || name == 'token_scores.json') {
        structure['tokenScoresJson'] = rel;
      } else if (name.startsWith('lexicon') && name.endsWith('.txt')) {
        // Prefer a generic lexicon.txt; only set once (first found).
        structure.putIfAbsent('lexicon', () => rel);
      }
    }

    if (await Directory(p.join(modelDir, 'espeak-ng-data')).exists()) {
      structure['dataDir'] = 'espeak-ng-data';
    }

    // test_wavs: use the first English-sounding wav as default reference audio.
    final testWavsDir = Directory(p.join(modelDir, 'test_wavs'));
    if (await testWavsDir.exists()) {
      String? refWav;
      await for (final entity in testWavsDir.list()) {
        if (entity is! File || !entity.path.endsWith('.wav')) continue;
        final name = p.basenameWithoutExtension(entity.path).toLowerCase();
        // Prefer short/simple names (bria, loona) over long descriptive ones.
        if (refWav == null || name.length < p.basenameWithoutExtension(refWav).length) {
          refWav = p.relative(entity.path, from: modelDir);
        }
      }
      if (refWav != null) structure['referenceWav'] = refWav;
    }

    return structure;
  }

  String _fixturePath(String lang) {
    final f = File(p.join(fixtureDir, '$lang.wav'));
    return f.existsSync() ? f.path : p.join(fixtureDir, 'en.wav');
  }

  Future<Float32List> _readWavSamples(String wavPath) async {
    final bytes = await File(wavPath).readAsBytes();
    const headerSize = 44;
    final count = (bytes.length - headerSize) ~/ 2;
    final samples = Float32List(count);
    for (var i = 0; i < count; i++) {
      final off = headerSize + i * 2;
      final raw = bytes[off] | (bytes[off + 1] << 8);
      final signed = raw > 32767 ? raw - 65536 : raw;
      samples[i] = signed / 32768.0;
    }
    return samples;
  }

  /// Detect supported languages from files inside the downloaded model directory.
  ///
  /// Priority:
  ///   1. test_wavs/ — language-named .wav files bundled by the model authors
  ///   2. Explicit language list file (lang_list.txt, languages.txt, …)
  ///   3. Whisper-style language tokens in tokens.txt (<|en|> or [en]),
  ///      only when the count is ≤ 50 (full-vocabulary models like NeMo
  ///      embed all ISO codes but are only trained on a subset)
  ///   4. Language name embedded in the model ID (e.g. -korean-, -english-)
  Future<List<String>> _detectLanguages(
    String modelDir,
    Map<String, dynamic> fileStructure,
  ) async {
    // 1. test_wavs/ directory — wav files named by language code are the
    //    most authoritative signal: the model authors chose these languages.
    final testWavsDir = Directory(p.join(modelDir, 'test_wavs'));
    if (await testWavsDir.exists()) {
      final langs = <String>{};
      await for (final entity in testWavsDir.list()) {
        if (entity is! File) continue;
        final name = p.basenameWithoutExtension(entity.path);
        if (RegExp(r'^[a-z]{2}$').hasMatch(name)) langs.add(name);
      }
      if (langs.isNotEmpty) return langs.toList()..sort();
    }

    // 2. Explicit language list file.
    final langListRel = fileStructure['langList'] as String?;
    if (langListRel != null) {
      final file = File(p.join(modelDir, langListRel));
      if (await file.exists()) {
        final lines = await file.readAsLines();
        final langs = _parseLanguageLines(lines);
        if (langs.isNotEmpty) return langs;
      }
    }

    // 3. Language tokens in tokens.txt (Whisper-style models).
    //    Cap at 50: NeMo and similar models embed the full ISO 639-1 set in
    //    their vocabulary even when only trained on a small language subset.
    final tokensRel = fileStructure['tokens'] as String?;
    if (tokensRel != null) {
      final file = File(p.join(modelDir, tokensRel));
      if (await file.exists()) {
        final lines = await file.readAsLines();
        final langs = _parseLanguageTokens(lines);
        if (langs.isNotEmpty && langs.length <= 50) return langs;
      }
    }

    // 4. Language name embedded in the model directory name.
    final dirName = p.basename(modelDir);
    final idLang = _detectLangFromId(dirName);
    if (idLang != null) return [idLang];

    return [];
  }

  /// Parse a language list file where each line is an ISO code or full name.
  ///
  /// Maps common full-word language names to ISO 639-1 codes, including
  /// languages like "korean" that do not use a 2-letter abbreviation pattern
  /// in some model naming conventions.
  List<String> _parseLanguageLines(List<String> lines) {
    final result = <String>{};
    for (final raw in lines) {
      final line = raw.trim().toLowerCase();
      if (line.isEmpty || line.startsWith('#')) continue;
      // Already a 2-letter ISO code.
      if (RegExp(r'^[a-z]{2}$').hasMatch(line)) {
        result.add(line);
        continue;
      }
      // Full language name → ISO code.
      final code = _languageNameToCode(line);
      if (code != null) result.add(code);
    }
    return result.toList()..sort();
  }

  /// Parse tokens.txt for Whisper-style language tokens: <|en|> or [en].
  ///
  /// Returns detected ISO 639-1 codes. Returns empty when fewer than 5 tokens
  /// are found — single-language models sometimes contain stray bracket tokens.
  List<String> _parseLanguageTokens(List<String> lines) {
    final whisper = RegExp(r'<\|([a-z]{2,3})\|>');
    final bracket = RegExp(r'^\[([a-z]{2})\]$');
    final result = <String>{};
    for (final line in lines) {
      final token = line.split(' ').first.trim();
      final wm = whisper.firstMatch(token);
      if (wm != null) {
        result.add(wm.group(1)!);
        continue;
      }
      final bm = bracket.firstMatch(token);
      if (bm != null) result.add(bm.group(1)!);
    }
    // Require at least 5 language tokens — avoids false positives.
    if (result.length < 5) return [];
    return result.toList()..sort();
  }

  /// Detect a single language from a model ID or directory name.
  ///
  /// Handles full language words (e.g. -korean-) as well as 2-letter ISO
  /// codes surrounded by dashes (e.g. -ko- or _ko_).
  String? _detectLangFromId(String id) {
    final lower = id.toLowerCase();

    // Check full language names first (special cases not covered by ISO codes).
    const namePatterns = [
      ('korean', 'ko'),
      ('english', 'en'),
      ('chinese', 'zh'),
      ('mandarin', 'zh'),
      ('japanese', 'ja'),
      ('french', 'fr'),
      ('german', 'de'),
      ('spanish', 'es'),
      ('portuguese', 'pt'),
      ('russian', 'ru'),
      ('arabic', 'ar'),
      ('hindi', 'hi'),
      ('italian', 'it'),
      ('dutch', 'nl'),
      ('polish', 'pl'),
      ('turkish', 'tr'),
      ('ukrainian', 'uk'),
      ('vietnamese', 'vi'),
      ('thai', 'th'),
      ('indonesian', 'id'),
      ('catalan', 'ca'),
      ('czech', 'cs'),
      ('danish', 'da'),
      ('finnish', 'fi'),
      ('greek', 'el'),
      ('hungarian', 'hu'),
      ('norwegian', 'no'),
      ('romanian', 'ro'),
      ('swedish', 'sv'),
    ];

    for (final (name, code) in namePatterns) {
      if (lower.contains('-$name-') ||
          lower.contains('_${name}_') ||
          lower.contains('-$name') ||
          lower.endsWith('_$name')) {
        return code;
      }
    }

    // 2-letter ISO code surrounded by dashes or underscores.
    final isoMatch = RegExp(r'[-_]([a-z]{2})[-_]').firstMatch(lower);
    if (isoMatch != null) return isoMatch.group(1);

    return null;
  }

  /// Map a full language name to its ISO 639-1 code, or null if unknown.
  String? _languageNameToCode(String name) {
    const map = {
      'korean': 'ko',
      'english': 'en',
      'chinese': 'zh',
      'mandarin': 'zh',
      'japanese': 'ja',
      'french': 'fr',
      'german': 'de',
      'spanish': 'es',
      'portuguese': 'pt',
      'russian': 'ru',
      'arabic': 'ar',
      'hindi': 'hi',
      'italian': 'it',
      'dutch': 'nl',
      'polish': 'pl',
      'turkish': 'tr',
      'ukrainian': 'uk',
      'vietnamese': 'vi',
      'thai': 'th',
      'indonesian': 'id',
      'catalan': 'ca',
      'czech': 'cs',
      'danish': 'da',
      'finnish': 'fi',
      'greek': 'el',
      'hungarian': 'hu',
      'norwegian': 'no',
      'romanian': 'ro',
      'swedish': 'sv',
    };
    return map[name];
  }

  bool _matchesLanguage(Map<String, dynamic> entry) {
    if (languages.isEmpty) return true;
    final entryLangs =
        (entry['languages'] as List<dynamic>? ?? []).cast<String>().toSet();
    if (entryLangs.isEmpty) return false;
    return entryLangs.intersection(languages).isNotEmpty;
  }

  void _appendNote(Map<String, dynamic> entry, String note) {
    final existing = entry['notes'] as String? ?? '';
    entry['notes'] = existing.isEmpty ? note : '$existing; $note';
  }
}
