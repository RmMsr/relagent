// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog_index.dart';
import 'entry_scope.dart';

/// Fetches new sherpa-onnx model assets from GitHub and merges them into
/// voice-models.json as untested entries.
class VoiceCatalogDiscovery {
  static const _apiBase = 'https://api.github.com/repos/k2-fsa/sherpa-onnx';
  static const _releaseTags = ['asr-models', 'tts-models'];
  static const _releaseBaseUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/tag';
  final CatalogIndex index;

  VoiceCatalogDiscovery(this.index);

  /// Fetch new assets from GitHub and add them to [entries] as untested.
  ///
  /// Assets outside [scope] (type/lang/arch) are skipped entirely — they
  /// are not added, so a later --discover with a broader scope will still
  /// pick them up.
  ///
  /// Returns the updated list. On network error, prints a warning and
  /// returns [entries] unchanged.
  Future<List<Map<String, dynamic>>> discover(
    List<Map<String, dynamic>> entries, {
    EntryScope scope = const EntryScope(),
  }) async {
    final existingIds = {for (final e in entries) e['id'] as String};
    final newEntries = <Map<String, dynamic>>[];
    var discovered = 0;

    for (final tag in _releaseTags) {
      print('[Discovery] Fetching $_releaseBaseUrl/$tag');
      final assets = await _fetchReleaseAssets(tag);
      if (assets == null) {
        print('[Discovery] Warning: Could not fetch $tag assets, skipping');
        continue;
      }

      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (!name.endsWith('.tar.bz2')) continue;

        final entry = _parseAssetFilename(
          name,
          asset['browser_download_url'] as String? ?? '',
          (asset['size'] as int? ?? 0) ~/ (1024 * 1024),
          tag,
        );

        final id = entry['id'] as String;
        if (existingIds.contains(id)) continue;
        if (!scope.matches(entry)) continue;

        existingIds.add(id);
        newEntries.add(entry);
        discovered++;
      }
    }

    print('[Discovery] Found $discovered new model entries');
    return [...entries, ...newEntries];
  }

  /// Re-derive architecture/origin/sourceUrl/displayName for every 'untested'
  /// entry in [scope], using the current filename parser. This is a pure,
  /// free (no network/download) recomputation from [id] — always run fresh,
  /// never treated as a one-time fixup, so parser improvements take effect
  /// on the very next --discover without anyone needing to remember a
  /// separate step.
  ///
  /// Entries with status 'approved' or 'failed' are left untouched: their
  /// architecture may reflect real file-structure detection at eval time
  /// (ground truth), which this filename-based guess must never overwrite.
  /// fileStructure/notes/status themselves are never touched here either
  /// way. [languages] is only filled in when currently empty.
  ///
  /// The "/ k2-fsa" distributor suffix on [origin] is normalized for every
  /// entry regardless of status — origin is never eval-derived, so that
  /// part is always safe.
  ///
  /// Returns the number of entries that were changed.
  int classify(
    List<Map<String, dynamic>> entries, {
    EntryScope scope = const EntryScope(),
  }) {
    var changed = 0;
    for (final entry in entries) {
      if (!scope.matches(entry)) continue;

      final currentOrigin = entry['origin'] as String? ?? '';
      final normalizedOrigin = _withDistributor(currentOrigin);
      if (normalizedOrigin != currentOrigin) {
        entry['origin'] = normalizedOrigin;
        changed++;
      }

      if (entry['status'] != 'untested') continue;

      final id = entry['id'] as String;
      _ParsedFilename parsed;
      try {
        parsed = _parseFilename(id);
      } catch (_) {
        continue;
      }
      if (parsed.architecture == 'unknown') continue;

      final beforeArchitecture = entry['architecture'];
      final beforeOrigin = entry['origin'];
      final beforeSourceUrl = entry['sourceUrl'];
      final beforeLanguages = entry['languages'];
      final beforeDisplayName = entry['displayName'];

      entry['architecture'] = parsed.architecture;
      entry['origin'] = _withDistributor(parsed.origin);
      entry['sourceUrl'] = parsed.sourceUrl;

      final existingLangs =
          (entry['languages'] as List<dynamic>? ?? []).cast<String>();
      if (existingLangs.isEmpty && parsed.languages.isNotEmpty) {
        entry['languages'] = parsed.languages;
      }
      final langsForDisplay =
          existingLangs.isNotEmpty ? existingLangs : parsed.languages;

      entry['displayName'] = parsed.displayNameOverride ??
          _deriveDisplayName(
            langsForDisplay,
            parsed.architecture,
            entry['type'] as String,
          );

      if (entry['architecture'] != beforeArchitecture ||
          entry['origin'] != beforeOrigin ||
          entry['sourceUrl'] != beforeSourceUrl ||
          entry['languages'] != beforeLanguages ||
          entry['displayName'] != beforeDisplayName) {
        changed++;
      }
    }
    return changed;
  }

  Future<List<dynamic>?> _fetchReleaseAssets(String tag) async {
    try {
      final uri = Uri.parse('$_apiBase/releases/tags/$tag');
      final response = await http
          .get(uri, headers: {'Accept': 'application/vnd.github.v3+json'})
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('[Discovery] HTTP ${response.statusCode} for $tag');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['assets'] as List<dynamic>?;
    } catch (e) {
      print('[Discovery] Network error for $tag: $e');
      return null;
    }
  }

  Map<String, dynamic> _parseAssetFilename(
    String filename,
    String downloadUrl,
    int downloadSizeMb,
    String releaseTag,
  ) {
    final base = filename.replaceAll('.tar.bz2', '');
    final id = base.replaceAll('.', '-');
    // Type is authoritative from the release tag, not the filename.
    final type = releaseTag == 'tts-models' ? 'tts' : 'asr';
    String architecture;
    List<String> languages;
    String origin;
    String sourceUrl;
    String? displayNameOverride;

    try {
      final parsed = _parseFilename(base);
      architecture = parsed.architecture;
      languages = parsed.languages;
      origin = parsed.origin;
      sourceUrl = parsed.sourceUrl;
      displayNameOverride = parsed.displayNameOverride;
    } catch (e) {
      architecture = 'unknown';
      languages = [];
      origin = 'unknown';
      sourceUrl = 'https://github.com/k2-fsa/sherpa-onnx';
    }

    final displayName = displayNameOverride ??
        _deriveDisplayName(languages, architecture, type);

    return {
      'id': id,
      'displayName': displayName,
      'type': type,
      'architecture': architecture,
      'languages': languages,
      'downloadUrl': downloadUrl,
      'downloadSizeMb': downloadSizeMb,
      'fileStructure': <String, String>{},
      'origin': _withDistributor(origin),
      'sourceUrl': sourceUrl,
      'speakerCount': 0,
      'releaseDate': _extractReleaseDate(base),
      'status': 'untested',
      'recommended': false,
      'notes': '',
    };
  }

  _ParsedFilename _parseFilename(String base) {
    if (base.startsWith('vits-piper-')) return _parsePiper(base);
    if (base.startsWith('kokoro-')) return _parseKokoro(base);
    if (base.contains('pocket-tts')) return _parsePocketTts(base);
    if (base.contains('omnilingual-asr')) return _parseOmnilingual(base);
    if (base.contains('sense-voice')) return _parseSenseVoice(base);
    if (base.contains('paraformer')) return _parseParaformer(base);
    if (base.contains('dolphin')) return _parseDolphin(base);
    if (base.contains('fire-red-asr')) return _parseFireRedAsr(base);
    if (base.contains('nemo-canary')) return _parseNemoCanary(base);
    // Must run before the generic zipformer/CTC checks below: icefall's old
    // pre-"sherpa-onnx-" naming has its own quirks (word order, "-mobile"
    // variants with a genuinely different, crash-prone internal shape) that
    // the generic patterns don't know to special-case.
    if (base.contains('icefall-asr')) return _parseIcefallAsr(base);
    if (RegExp(r'zipformer2?-ctc').hasMatch(base) ||
        base.contains('streaming-conformer-ctc')) {
      return _parseCtcModel(base);
    }
    if ((base.contains('streaming-zipformer') ||
            base.contains('zipformer-streaming')) &&
        !base.contains('ctc')) {
      return _parseStreamingZipformer(base);
    }
    if (base.contains('streaming-conformer-')) {
      return _parseStreamingConformer(base);
    }
    if (base.contains('nemo-parakeet') ||
        base.contains('nemo-transducer') ||
        base.contains('fast-conformer-transducer')) {
      return _parseNemoTransducer(base);
    }
    if (base.contains('nemo') &&
        base.contains('ctc') &&
        base.contains('streaming')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'onlineNemoCtc',
        languages: _extractLanguagesFromFilename(base),
        origin: 'NVIDIA NeMo / k2-fsa',
        sourceUrl: 'https://github.com/NVIDIA-NeMo/Speech',
      );
    }
    if ((base.contains('nemo-ctc') || base.contains('fast-conformer-ctc')) ||
        (base.contains('nemo-stt') && base.contains('fastconformer'))) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'nemoCtc',
        languages: _extractLanguagesFromFilename(base),
        origin: base.contains('giga-am')
            ? 'GigaAM / Sber (NeMo toolkit)'
            : 'NVIDIA NeMo (offline CTC)',
        sourceUrl: base.contains('giga-am')
            ? 'https://github.com/salute-developers/GigaAM'
            : 'https://github.com/NVIDIA-NeMo/Speech',
      );
    }
    if (base.contains('nemotron')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'nemotronStreaming',
        languages: _extractLanguagesFromFilename(base),
        origin: 'NVIDIA Nemotron',
        sourceUrl: 'https://github.com/NVIDIA-NeMo/Speech',
      );
    }
    if (base.contains('whisper')) return _parseWhisper(base);
    if (base.contains('moonshine')) return _parseMoonshine(base);
    if (base.contains('wenetspeech-') &&
        RegExp(r'wenetspeech-[a-z]+-u\d').hasMatch(base)) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'wenetCtc',
        languages: _extractLanguagesFromFilename(base),
        origin: 'WeNet (WenetSpeech dialect CTC)',
        sourceUrl: 'https://github.com/wenet-e2e/wenet',
      );
    }
    if (base.contains('-wenet-')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'wenetCtc',
        languages: _extractLanguagesFromFilename(base),
        origin: 'WeNet',
        sourceUrl: 'https://github.com/wenet-e2e/wenet',
      );
    }
    if (base.contains('zipformer')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'zipformerOfflineTransducer',
        languages: _extractLanguagesFromFilename(base),
        origin: 'Next-gen Kaldi / k2-fsa',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    if (base.contains('x-asr-zipformer-transducer')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'transducer',
        languages: _extractLanguagesFromFilename(base),
        origin: 'Next-gen Kaldi / k2-fsa',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    if (base.contains('funasr-nano')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'funasrNano',
        languages: _extractLanguagesFromFilename(base),
        origin: 'FunASR (Alibaba)',
        sourceUrl: 'https://github.com/modelscope/FunASR',
      );
    }
    if (RegExp(r'^(sherpa-onnx-)?(conformer|lstm)-').hasMatch(base)) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'nextGenKaldiTransducer',
        languages: _extractLanguagesFromFilename(base),
        origin: 'Next-gen Kaldi / k2-fsa (icefall)',
        sourceUrl: 'https://github.com/k2-fsa/icefall',
      );
    }
    if (base.contains('tdnn-yesno')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'legacyKaldi',
        languages: const ['en'],
        origin: 'Next-gen Kaldi / k2-fsa (yesno demo)',
        sourceUrl: 'https://github.com/k2-fsa/icefall',
        displayNameOverride: 'Yes/No Demo - TDNN',
      );
    }
    if (base.contains('telespeech-ctc')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'telespeechCtc',
        languages: _extractLanguagesFromFilename(base),
        origin: 'TeleSpeech-ASR / China Telecom',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    if (base.contains('medasr-ctc')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'medAsrCtc',
        languages: _extractLanguagesFromFilename(base),
        origin: 'MedASR (medical-domain CTC ASR)',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    if (base.contains('t-one')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'tOne',
        languages: _extractLanguagesFromFilename(base),
        origin: 'T-one (Russian streaming ASR)',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    if (base.contains('cohere-transcribe')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'cohereTranscribe',
        languages: [],
        origin: 'Cohere Transcribe',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    if (base.contains('qwen') && base.contains('asr')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'qwenAsr',
        languages: [],
        origin: 'Qwen-ASR / Alibaba',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    if (base.contains('vits-coqui')) return _parseVitsCoqui(base);
    if (base.contains('vits-mimic')) return _parseVitsMimic(base);
    if (base.contains('vits-mms')) return _parseVitsMms(base);
    if (base.contains('-hf-')) return _parseVitsHf(base);
    if (base.contains('kitten-')) {
      return _ParsedFilename(
        type: 'tts',
        architecture: 'kittenTts',
        languages: _extractLanguagesFromFilename(base),
        origin: 'Kitten TTS',
        sourceUrl: 'https://github.com/KittenML/KittenTTS',
      );
    }
    if (base.contains('zipvoice')) {
      return _ParsedFilename(
        type: 'tts',
        architecture: 'zipvoice',
        languages: _extractLanguagesFromFilename(base),
        origin: 'ZipVoice / k2-fsa',
        sourceUrl: 'https://github.com/k2-fsa/ZipVoice',
      );
    }
    if (base.startsWith('matcha-icefall-')) {
      return _ParsedFilename(
        type: 'tts',
        architecture: 'matchaTts',
        languages: _extractLanguagesFromFilename(base),
        origin: 'Next-gen Kaldi / k2-fsa (Matcha-TTS)',
        sourceUrl: 'https://github.com/k2-fsa/icefall',
      );
    }
    if (base.startsWith('matcha-tts-')) {
      return _ParsedFilename(
        type: 'tts',
        architecture: 'matchaTts',
        languages: _extractLanguagesFromFilename(base),
        origin: 'Matcha-TTS',
        sourceUrl: 'https://github.com/shivammehta25/Matcha-TTS',
      );
    }
    if (base.contains('melo-tts')) {
      return _ParsedFilename(
        type: 'tts',
        architecture: 'meloTts',
        languages: _extractLanguagesFromFilename(base),
        origin: 'MeloTTS / MyShell',
        sourceUrl: 'https://github.com/myshell-ai/MeloTTS',
      );
    }
    if (base.contains('supertonic')) {
      return _ParsedFilename(
        type: 'tts',
        architecture: 'supertonicTts',
        languages: const ['en'],
        origin: 'Supertonic TTS',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    if (base.contains('vits-inflect')) {
      return _ParsedFilename(
        type: 'tts',
        architecture: 'vitsInflect',
        languages: _extractLanguagesFromFilename(base),
        origin: 'Inflect TTS',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    if (base.contains('vits-icefall-') ||
        RegExp(r'vits-(ljs|vctk|zh-(ll|aishell))').hasMatch(base)) {
      return _ParsedFilename(
        type: 'tts',
        architecture: 'vitsIcefall',
        languages: _extractLanguagesFromFilename(base),
        origin: 'Next-gen Kaldi / k2-fsa (icefall VITS)',
        sourceUrl: 'https://github.com/k2-fsa/icefall',
      );
    }
    if (base == 'espeak-ng-data') {
      return _ParsedFilename(
        type: 'tts',
        architecture: 'supportAsset',
        languages: const [],
        origin: 'espeak-ng (support data, not a model)',
        sourceUrl: 'https://github.com/espeak-ng/espeak-ng',
        displayNameOverride: 'eSpeak NG Data (support asset)',
      );
    }
    if (base == 'librknnrt-android') {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'supportAsset',
        languages: const [],
        origin: 'RKNN runtime library (not a model)',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
        displayNameOverride: 'RKNN Runtime (Android, support asset)',
      );
    }
    if (base == 'spoken-language-identification-test-wavs') {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'supportAsset',
        languages: const [],
        origin: 'Test fixtures (not a model)',
        sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
        displayNameOverride: 'Spoken Language ID Test WAVs (fixture)',
      );
    }
    return _ParsedFilename(
      type: 'asr', architecture: 'unknown', languages: [],
      origin: 'unknown', sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
    );
  }

  _ParsedFilename _parseOmnilingual(String base) {
    final sizeMatch = RegExp(r'-(\d+[MB])-ctc').firstMatch(base);
    final sizeLabel = sizeMatch != null ? ' ${sizeMatch.group(1)}' : '';
    return _ParsedFilename(
      type: 'asr',
      // NOT the real 'ctc' enum value: confirmed by a real eval run that
      // Omnilingual's downloaded file structure doesn't have an 'encoder'
      // key (_inspectDirectory only assigns that key when the filename
      // contains "encoder"; Omnilingual's onnx file is generically named),
      // so the 'ctc' architecture's zipformer2Ctc builder crashes with
      // "Null check operator used on a null value" on files['encoder']!.
      // The ModelArchitecture.ctc doc comment names omnilingual as the
      // canonical example, but that's aspirational — the actual builder
      // doesn't support this file layout yet.
      architecture: 'omnilingualCtc',
      // 1600 languages — impractical/meaningless to enumerate. 'multi' is a
      // wildcard sentinel: EntryScope and ModelCatalog.byLanguage treat it
      // as matching any requested language code.
      languages: const ['multi'],
      origin: 'Omnilingual ASR / Meta FAIR',
      sourceUrl: 'https://github.com/facebookresearch/omnilingual-asr',
      displayNameOverride: 'Omnilingual ASR$sizeLabel (1600 languages) - CTC',
    );
  }

  _ParsedFilename _parseSenseVoice(String base) {
    return _ParsedFilename(
      type: 'asr',
      architecture: 'senseVoice',
      languages: _extractLanguagesFromFilename(base),
      origin: 'SenseVoice / FunASR (Alibaba)',
      sourceUrl: 'https://github.com/QwenAudio/SenseVoice',
    );
  }

  _ParsedFilename _parseParaformer(String base) {
    return _ParsedFilename(
      type: 'asr',
      architecture: 'paraformer',
      languages: _extractLanguagesFromFilename(base),
      origin: 'Paraformer / FunASR (Alibaba)',
      sourceUrl: 'https://github.com/modelscope/FunASR',
    );
  }

  _ParsedFilename _parseDolphin(String base) {
    return _ParsedFilename(
      type: 'asr',
      architecture: 'dolphinCtc',
      languages: _extractLanguagesFromFilename(base),
      origin: 'Dolphin / DataOcean AI',
      sourceUrl: 'https://github.com/DataoceanAI/Dolphin',
    );
  }

  _ParsedFilename _parseFireRedAsr(String base) {
    return _ParsedFilename(
      type: 'asr',
      architecture: 'fireRedAsr',
      languages: _extractLanguagesFromFilename(base),
      origin: 'FireRedASR / Xiaohongshu (RedNote)',
      sourceUrl: 'https://github.com/FireRedTeam/FireRedASR',
    );
  }

  _ParsedFilename _parseNemoCanary(String base) {
    return _ParsedFilename(
      type: 'asr',
      architecture: 'nemoCanary',
      languages: _extractLanguagesFromFilename(base),
      origin: 'NVIDIA NeMo Canary',
      sourceUrl: 'https://github.com/NVIDIA-NeMo/Speech',
    );
  }

  _ParsedFilename _parseWhisper(String base) {
    return _ParsedFilename(
      type: 'asr',
      architecture: 'whisper',
      languages: base.contains('-en') || base.endsWith('en')
          ? const ['en']
          : _extractLanguagesFromFilename(base),
      origin: 'Whisper / OpenAI',
      sourceUrl: 'https://github.com/openai/whisper',
    );
  }

  _ParsedFilename _parseMoonshine(String base) {
    return _ParsedFilename(
      type: 'asr',
      architecture: 'moonshine',
      languages: _extractLanguagesFromFilename(base),
      origin: 'Moonshine / Useful Sensors',
      sourceUrl: 'https://github.com/moonshine-ai/moonshine',
    );
  }

  _ParsedFilename _parseIcefallAsr(String base) {
    final isZipformer = base.contains('zipformer');
    final isStreaming = base.contains('streaming');
    // "-mobile" variants are a separate, phone-optimized export with a
    // different internal layer/context config — confirmed structurally
    // incompatible with this app's fixed-shape streaming zipformer builder
    // (native ONNX Reshape crash, not a graceful error) even though the
    // non-mobile sibling under the same name works fine.
    final isMobile = base.contains('mobile');
    var languages = _extractLanguagesFromFilename(base);
    if (languages.isEmpty && base.contains('wenetspeech')) languages = ['zh'];
    if (isZipformer && isStreaming && !isMobile) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'transducer',
        languages: languages,
        origin: 'Next-gen Kaldi / k2-fsa (icefall)',
        sourceUrl: 'https://github.com/k2-fsa/icefall',
      );
    }
    return _ParsedFilename(
      type: 'asr',
      architecture: isZipformer
          ? (isMobile ? 'zipformerStreamingMobile' : 'zipformerOfflineTransducer')
          : 'nextGenKaldiTransducer',
      languages: languages,
      origin: 'Next-gen Kaldi / k2-fsa (icefall)',
      sourceUrl: 'https://github.com/k2-fsa/icefall',
    );
  }

  _ParsedFilename _parseVitsCoqui(String base) {
    final langMatch = RegExp(r'vits-coqui-([a-z]{2})-').firstMatch(base);
    return _ParsedFilename(
      type: 'tts',
      architecture: 'vitsCoqui',
      languages: langMatch != null ? [langMatch.group(1)!] : const [],
      origin: 'Coqui TTS',
      sourceUrl: 'https://github.com/coqui-ai/TTS',
    );
  }

  _ParsedFilename _parseVitsMimic(String base) {
    final langMatch = RegExp(r'vits-mimic\d*-([a-z]{2})').firstMatch(base);
    return _ParsedFilename(
      type: 'tts',
      architecture: 'vitsMimic3',
      languages: langMatch != null ? [langMatch.group(1)!] : const [],
      origin: 'Mimic 3 / Mycroft AI',
      sourceUrl: 'https://github.com/MycroftAI/mimic3',
    );
  }

  static const _mmsIso3ToIso2 = {
    'deu': 'de', 'eng': 'en', 'fra': 'fr', 'rus': 'ru',
    'spa': 'es', 'tha': 'th', 'ukr': 'uk',
  };

  _ParsedFilename _parseVitsMms(String base) {
    final iso3Match = RegExp(r'vits-mms-([a-z]{3})$').firstMatch(base);
    final iso3 = iso3Match?.group(1);
    final iso2 = iso3 != null ? _mmsIso3ToIso2[iso3] : null;
    return _ParsedFilename(
      type: 'tts',
      architecture: 'vitsMms',
      languages: iso2 != null ? [iso2] : const [],
      origin: 'MMS / Meta',
      sourceUrl:
          'https://github.com/facebookresearch/fairseq/tree/main/examples/mms',
    );
  }

  _ParsedFilename _parseVitsHf(String base) {
    return _ParsedFilename(
      type: 'tts',
      architecture: 'vits',
      languages: _extractLanguagesFromFilename(base),
      origin: 'VITS (community voices, HuggingFace)',
      sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
    );
  }

  _ParsedFilename _parsePiper(String base) {
    final parts = base.split('-');
    if (parts.length < 4) {
      return _ParsedFilename(
        type: 'tts', architecture: 'unknown', languages: [],
        origin: 'unknown', sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    final langCode = parts[2];
    final langIso = langCode.split('_').first.toLowerCase();
    final quality = parts.length >= 5 ? parts[4] : '';
    return _ParsedFilename(
      type: 'tts',
      architecture: 'vitsPiper',
      languages: [langIso],
      origin: 'Piper / Rhasspy',
      sourceUrl: 'https://github.com/rhasspy/piper',
      qualityHint: quality,
    );
  }

  _ParsedFilename _parsePocketTts(String base) {
    final langs = _extractLanguagesFromFilename(base);
    return _ParsedFilename(
      type: 'tts',
      architecture: 'pocket',
      languages: langs.isNotEmpty ? langs : ['en'],
      origin: 'Pocket TTS / Kyutai Labs',
      sourceUrl: 'https://github.com/kyutai-labs/pocket-tts',
    );
  }

  _ParsedFilename _parseKokoro(String base) {
    // Multilingual models (v1.0+) carry no single language code in the filename.
    if (base.contains('multi-lang')) {
      return _ParsedFilename(
        type: 'tts',
        architecture: 'kokoro',
        // Kokoro v1.0+ multi-lang supported languages per hexgrad/kokoro docs.
        languages: ['de', 'en', 'es', 'fr', 'hi', 'it', 'ja', 'ko', 'pt', 'zh'],
        origin: 'Kokoro / Hexgrad',
        sourceUrl: 'https://github.com/hexgrad/kokoro',
      );
    }
    final langMatch = RegExp(r'-([a-z]{2})-').firstMatch(base);
    final lang = langMatch?.group(1) ?? 'en';
    return _ParsedFilename(
      type: 'tts',
      architecture: 'kokoro',
      languages: [lang],
      origin: 'Kokoro / Hexgrad',
      sourceUrl: 'https://github.com/hexgrad/kokoro',
    );
  }

  _ParsedFilename _parseStreamingZipformer(String base) {
    final langs = _extractLanguagesFromFilename(base);
    return _ParsedFilename(
      type: 'asr',
      architecture: 'transducer',
      languages: langs,
      origin: 'Next-gen Kaldi / k2-fsa',
      sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
    );
  }

  _ParsedFilename _parseCtcModel(String base) {
    final langs = _extractLanguagesFromFilename(base);
    return _ParsedFilename(
      type: 'asr',
      architecture: 'ctc',
      languages: langs,
      origin: 'Next-gen Kaldi / k2-fsa',
      sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
    );
  }

  _ParsedFilename _parseStreamingConformer(String base) {
    final langs = _extractLanguagesFromFilename(base);
    return _ParsedFilename(
      type: 'asr',
      architecture: 'transducer',
      languages: langs,
      origin: 'Next-gen Kaldi / k2-fsa',
      sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
    );
  }

  _ParsedFilename _parseNemoTransducer(String base) {
    // Hardcoded language lists for models whose filenames carry no language
    // signal. Verified against https://k2-fsa.github.io/sherpa/onnx/
    // pretrained_models/offline-transducer/nemo-transducer-models.html
    const _knownNemoLanguages = <String, List<String>>{
      // Parakeet TDT 0.6B v2 — English only
      'parakeet-tdt-0-6b-v2': ['en'],
      // Parakeet TDT 0.6B v3 — 25 European languages
      'parakeet-tdt-0-6b-v3': [
        'bg', 'cs', 'da', 'de', 'el', 'en', 'es', 'et', 'fi', 'fr',
        'hr', 'hu', 'it', 'lt', 'lv', 'mt', 'nl', 'pl', 'pt', 'ro',
        'ru', 'sk', 'sl', 'sv', 'uk',
      ],
    };

    // Match against known patterns (strip quantisation suffix before lookup).
    List<String> langs = [];
    for (final entry in _knownNemoLanguages.entries) {
      if (base.contains(entry.key)) {
        langs = entry.value;
        break;
      }
    }
    if (langs.isEmpty) langs = _extractLanguagesFromFilename(base);

    return _ParsedFilename(
      type: 'asr',
      architecture: 'offlineNemoTransducer',
      languages: langs,
      origin: 'NVIDIA NeMo / k2-fsa',
      sourceUrl: 'https://github.com/NVIDIA-NeMo/Speech',
    );
  }

  // Spelled-out language words that show up in filenames instead of codes
  // (e.g. "zipformer-cantonese", "giga-am-russian").
  static const _spelledOutLanguages = {
    'cantonese': 'yue', 'thai': 'th', 'korean': 'ko', 'russian': 'ru',
    'vietnamese': 'vi', 'mandarin': 'zh',
  };

  // 3-letter codes that appear as their own dash-segment (mostly Chinese
  // dialects, which have no 2-letter ISO 639-1 code).
  static const _threeLetterLanguageCodes = {'yue', 'wuu'};

  // 2-letter segments that show up in filenames for reasons unrelated to
  // language (packaging/corpus markers) and would otherwise false-positive
  // against the generic 2-letter code check.
  static const _nonLanguageTwoLetterTokens = {
    'hf', // "-hf-" HuggingFace-hosted community voice marker
    'll', // unclear vits-zh-ll suffix, not a language
    'cv', // "cv-corpus" (Common Voice) — corpus name, not Chuvash here
    'ng', // "espeak-ng" — library name, not a language
  };

  List<String> _extractLanguagesFromFilename(String base) {
    final langs = <String>[];
    for (final segment in base.split('-')) {
      // Plain 2-letter code: zh, en, de
      if (segment.length == 2 &&
          RegExp(r'^[a-z]{2}$').hasMatch(segment) &&
          !_nonLanguageTwoLetterTokens.contains(segment)) {
        langs.add(segment);
      // Underscore-joined codes: ar_en_id_ja_ru_th_vi_zh
      } else if (RegExp(r'^[a-z]{2}(?:_[a-z]{2})+$').hasMatch(segment)) {
        langs.addAll(segment.split('_'));
      } else if (_threeLetterLanguageCodes.contains(segment)) {
        langs.add(segment);
      } else if (_spelledOutLanguages.containsKey(segment)) {
        langs.add(_spelledOutLanguages[segment]!);
      }
    }
    return {...langs}.toList(); // de-duplicate while preserving order
  }

  String _extractReleaseDate(String base) {
    final dateMatch = RegExp(r'(\d{4})-(\d{2})-\d{2}').firstMatch(base);
    if (dateMatch != null) return '${dateMatch.group(1)}-${dateMatch.group(2)}';
    final yearMatch = RegExp(r'(\d{4})').firstMatch(base);
    if (yearMatch != null) return yearMatch.group(1)!;
    return '';
  }

  /// Every entry in this catalog is distributed via k2-fsa/sherpa-onnx's
  /// GitHub releases (see [_apiBase]) — that's true regardless of who
  /// created the underlying model, so it's appended to every origin string
  /// rather than only the families where a "/ k2-fsa" suffix happened to
  /// already be present.
  String _withDistributor(String origin) {
    if (origin.contains('k2-fsa')) return origin;
    return '$origin / k2-fsa';
  }

  String _deriveDisplayName(
    List<String> languages,
    String architecture,
    String type,
  ) {
    final langLabel = languages.contains('multi')
        ? 'Multilingual'
        : languages.length == 1
            ? _languageLabel(languages.first)
            : languages.length > 1
                ? 'Multilingual (${languages.length} languages)'
                : 'Unknown';
    final archLabel = _architectureLabel(architecture);
    return '$langLabel - $archLabel';
  }

  String _languageLabel(String code) {
    const labels = {
      'en': 'English',  'de': 'German',     'fr': 'French',     'es': 'Spanish',
      'it': 'Italian',  'nl': 'Dutch',       'pl': 'Polish',     'ru': 'Russian',
      'sv': 'Swedish',  'pt': 'Portuguese',  'cs': 'Czech',      'da': 'Danish',
      'fi': 'Finnish',  'nb': 'Norwegian',   'no': 'Norwegian',  'el': 'Greek',
      'ro': 'Romanian', 'sk': 'Slovak',      'sl': 'Slovenian',  'sr': 'Serbian',
      'uk': 'Ukrainian','lv': 'Latvian',     'lb': 'Luxembourgish',
      'ca': 'Catalan',  'cy': 'Welsh',       'is': 'Icelandic',
      'tr': 'Turkish',  'hu': 'Hungarian',   'ar': 'Arabic',     'fa': 'Persian',
      'hi': 'Hindi',    'bn': 'Bengali',     'ml': 'Malayalam',  'ne': 'Nepali',
      'zh': 'Chinese',  'ja': 'Japanese',    'ko': 'Korean',     'th': 'Thai',
      'vi': 'Vietnamese','id': 'Indonesian', 'sw': 'Swahili',
      'am': 'Amharic',  'ka': 'Georgian',    'kk': 'Kazakh',
      'yue': 'Cantonese', 'wu': 'Wu Chinese', 'wuu': 'Wu Chinese',
      'ga': 'Irish',      'mt': 'Maltese',    'et': 'Estonian',
      'gu': 'Gujarati',
    };
    return labels[code] ?? code.toUpperCase();
  }

  String _architectureLabel(String arch) {
    const labels = {
      'transducer': 'Zipformer', 'ctc': 'CTC', 'vitsPiper': 'Piper',
      'kokoro': 'Kokoro', 'onlineNemoCtc': 'NeMo CTC',
      'offlineNemoTransducer': 'Parakeet TDT', 'pocket': 'Pocket TTS',
      // Catalog-only labels below: these do not map to a runtime-supported
      // ModelArchitecture value (see model_architecture.dart). They exist so
      // the catalog can show a real name instead of "unknown" — at eval
      // time these fall back to file-structure detection exactly as
      // 'unknown' would, so using them is a display-only, zero-risk change.
      'senseVoice': 'SenseVoice', 'paraformer': 'Paraformer',
      'dolphinCtc': 'Dolphin CTC', 'fireRedAsr': 'FireRedASR',
      'nemoCanary': 'NeMo Canary', 'nemoCtc': 'NeMo CTC (offline)',
      'nemotronStreaming': 'Nemotron Streaming', 'whisper': 'Whisper',
      'moonshine': 'Moonshine', 'wenetCtc': 'WeNet CTC',
      'zipformerOfflineTransducer': 'Zipformer (offline)',
      'zipformerStreamingMobile': 'Zipformer Streaming (mobile)',
      'omnilingualCtc': 'Omnilingual CTC',
      'funasrNano': 'FunASR Nano',
      'nextGenKaldiTransducer': 'Next-gen Kaldi Transducer',
      'legacyKaldi': 'Legacy Kaldi', 'telespeechCtc': 'TeleSpeech CTC',
      'medAsrCtc': 'MedASR CTC', 'tOne': 'T-one',
      'cohereTranscribe': 'Cohere Transcribe', 'qwenAsr': 'Qwen ASR',
      'vitsCoqui': 'Coqui VITS', 'vitsMimic3': 'Mimic 3',
      'vitsMms': 'MMS VITS', 'vits': 'VITS', 'kittenTts': 'Kitten TTS',
      'zipvoice': 'ZipVoice', 'matchaTts': 'Matcha-TTS',
      'meloTts': 'MeloTTS', 'supertonicTts': 'Supertonic TTS',
      'vitsInflect': 'Inflect VITS', 'vitsIcefall': 'VITS (icefall)',
      'supportAsset': 'Support Asset',
    };
    return labels[arch] ?? arch;
  }
}

class _ParsedFilename {
  final String type;
  final String architecture;
  final List<String> languages;
  final String origin;
  final String sourceUrl;
  final String qualityHint;
  final String? displayNameOverride;

  _ParsedFilename({
    required this.type,
    required this.architecture,
    required this.languages,
    required this.origin,
    required this.sourceUrl,
    this.qualityHint = '',
    this.displayNameOverride,
  });
}
