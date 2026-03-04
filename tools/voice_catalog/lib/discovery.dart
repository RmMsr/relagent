// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog_index.dart';

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
  /// Returns the updated list. On network error, prints a warning and
  /// returns [entries] unchanged.
  Future<List<Map<String, dynamic>>> discover(
    List<Map<String, dynamic>> entries,
  ) async {
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

        existingIds.add(id);
        newEntries.add(entry);
        discovered++;
      }
    }

    print('[Discovery] Found $discovered new model entries');
    return [...entries, ...newEntries];
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

    try {
      final parsed = _parseFilename(base);
      architecture = parsed.architecture;
      languages = parsed.languages;
      origin = parsed.origin;
      sourceUrl = parsed.sourceUrl;
    } catch (e) {
      architecture = 'unknown';
      languages = [];
      origin = 'unknown';
      sourceUrl = 'https://github.com/k2-fsa/sherpa-onnx';
    }

    final displayName = _deriveDisplayName(languages, architecture, type);

    return {
      'id': id,
      'displayName': displayName,
      'type': type,
      'architecture': architecture,
      'languages': languages,
      'downloadUrl': downloadUrl,
      'downloadSizeMb': downloadSizeMb,
      'fileStructure': <String, String>{},
      'origin': origin,
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
    if (base.contains('streaming-zipformer') && !base.contains('ctc')) {
      return _parseStreamingZipformer(base);
    }
    if (base.contains('zipformer2-ctc') ||
        base.contains('streaming-conformer-ctc')) {
      return _parseCtcModel(base);
    }
    if (base.contains('streaming-conformer-')) {
      return _parseStreamingConformer(base);
    }
    if (base.contains('nemo-parakeet') || base.contains('nemo-transducer')) {
      return _parseNemoTransducer(base);
    }
    if (base.contains('nemo-ctc') && base.contains('streaming')) {
      return _ParsedFilename(
        type: 'asr',
        architecture: 'onlineNemoCtc',
        languages: _extractLanguagesFromFilename(base),
        origin: 'NVIDIA NeMo / k2-fsa',
        sourceUrl: 'https://github.com/NVIDIA/NeMo',
      );
    }
    return _ParsedFilename(
      type: 'asr', architecture: 'unknown', languages: [],
      origin: 'unknown', sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
    );
  }

  _ParsedFilename _parsePiper(String base) {
    final parts = base.split('-');
    if (parts.length < 5) {
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
      origin: 'Pocket TTS / k2-fsa',
      sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
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
      sourceUrl: 'https://github.com/NVIDIA/NeMo',
    );
  }

  List<String> _extractLanguagesFromFilename(String base) {
    final langs = <String>[];
    for (final segment in base.split('-')) {
      // Plain 2-letter code: zh, en, de
      if (segment.length == 2 && RegExp(r'^[a-z]{2}$').hasMatch(segment)) {
        langs.add(segment);
      // Underscore-joined codes: ar_en_id_ja_ru_th_vi_zh
      } else if (RegExp(r'^[a-z]{2}(?:_[a-z]{2})+$').hasMatch(segment)) {
        langs.addAll(segment.split('_'));
      }
    }
    return langs;
  }

  String _extractReleaseDate(String base) {
    final dateMatch = RegExp(r'(\d{4})-(\d{2})-\d{2}').firstMatch(base);
    if (dateMatch != null) return '${dateMatch.group(1)}-${dateMatch.group(2)}';
    final yearMatch = RegExp(r'(\d{4})').firstMatch(base);
    if (yearMatch != null) return yearMatch.group(1)!;
    return '';
  }

  String _deriveDisplayName(
    List<String> languages,
    String architecture,
    String type,
  ) {
    final langLabel = languages.length == 1
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
    };
    return labels[code] ?? code.toUpperCase();
  }

  String _architectureLabel(String arch) {
    const labels = {
      'transducer': 'Zipformer', 'ctc': 'CTC', 'vitsPiper': 'Piper',
      'kokoro': 'Kokoro', 'onlineNemoCtc': 'NeMo CTC',
      'offlineNemoTransducer': 'Parakeet TDT', 'pocket': 'Pocket TTS',
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

  _ParsedFilename({
    required this.type,
    required this.architecture,
    required this.languages,
    required this.origin,
    required this.sourceUrl,
    this.qualityHint = '',
  });
}
