// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog_index.dart';

/// Fetches new sherpa-onnx model assets from GitHub and merges them into
/// voice-models.json as untested entries.
class VoiceCatalogDiscovery {
  static const _apiBase = 'https://api.github.com/repos/k2-fsa/sherpa-onnx';
  static const _releaseTags = ['asr-models', 'tts-models'];
  static const _supportedLanguages = {
    'en', 'de', 'fr', 'es', 'it', 'nl', 'pl', 'ru', 'sv', 'pt', 'cs',
  };

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
  ) {
    final base = filename.replaceAll('.tar.bz2', '');
    final id = base.replaceAll('.', '-');

    // Try to parse type, architecture, and languages from the filename.
    String type;
    String architecture;
    List<String> languages;
    String origin;
    String sourceUrl;

    try {
      final parsed = _parseFilename(base);
      type = parsed.type;
      architecture = parsed.architecture;
      languages = parsed.languages;
      origin = parsed.origin;
      sourceUrl = parsed.sourceUrl;
    } catch (e) {
      type = 'asr';
      architecture = 'unknown';
      languages = [];
      origin = 'unknown';
      sourceUrl = 'https://github.com/k2-fsa/sherpa-onnx';
    }

    // Derive a display name from languages and architecture.
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
    // TTS: vits-piper-{lang_code}-{voice}-{quality}[-int8]
    if (base.startsWith('vits-piper-')) {
      return _parsePiper(base);
    }
    // TTS: kokoro-[int8-]{lang}-{version}
    if (base.startsWith('kokoro-')) {
      return _parseKokoro(base);
    }
    // TTS: vits-matcha- (unsupported architecture)
    if (base.startsWith('vits-matcha-')) {
      return _ParsedFilename(
        type: 'tts', architecture: 'unknown', languages: [],
        origin: 'unknown', sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }
    // ASR: sherpa-onnx-streaming-zipformer-{lang}-...
    if (base.contains('streaming-zipformer') && !base.contains('ctc')) {
      return _parseStreamingZipformer(base);
    }
    // ASR: sherpa-onnx-streaming-zipformer2-ctc-...
    if (base.contains('zipformer2-ctc') || base.contains('streaming-conformer-ctc')) {
      return _parseCtcModel(base);
    }
    // ASR: sherpa-onnx-streaming-conformer-...
    if (base.contains('streaming-conformer-')) {
      return _parseStreamingConformer(base);
    }
    // ASR: sherpa-onnx-nemo-parakeet-...
    if (base.contains('nemo-parakeet') || base.contains('nemo-transducer')) {
      return _parseNemoTransducer(base);
    }
    // ASR: online-nemo-ctc
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
    // vits-piper-en_US-lessac-medium-int8
    final parts = base.split('-');
    // parts[0]=vits, parts[1]=piper, parts[2]=lang_code, parts[3]=voice, parts[4]=quality
    if (parts.length < 5) {
      return _ParsedFilename(
        type: 'tts', architecture: 'unknown', languages: [],
        origin: 'unknown', sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
      );
    }

    final langCode = parts[2]; // e.g. en_US, de_DE
    final langIso = langCode.split('_').first.toLowerCase();
    final quality = parts.length >= 5 ? parts[4] : '';

    // Note: low/x_low quality filtering is done in the filter phase, not here.
    return _ParsedFilename(
      type: 'tts',
      architecture: 'vitsPiper',
      languages: [langIso],
      origin: 'Piper / Rhasspy',
      sourceUrl: 'https://github.com/rhasspy/piper',
      qualityHint: quality,
    );
  }

  _ParsedFilename _parseKokoro(String base) {
    // kokoro-int8-en-v0_19 or kokoro-en-v0_19
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
      languages: langs.isEmpty ? ['en'] : langs,
      origin: 'Next-gen Kaldi / k2-fsa',
      sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
    );
  }

  _ParsedFilename _parseCtcModel(String base) {
    final langs = _extractLanguagesFromFilename(base);
    return _ParsedFilename(
      type: 'asr',
      architecture: 'ctc',
      languages: langs.isEmpty ? ['en'] : langs,
      origin: 'Next-gen Kaldi / k2-fsa',
      sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
    );
  }

  _ParsedFilename _parseStreamingConformer(String base) {
    final langs = _extractLanguagesFromFilename(base);
    return _ParsedFilename(
      type: 'asr',
      architecture: 'transducer',
      languages: langs.isEmpty ? ['en'] : langs,
      origin: 'Next-gen Kaldi / k2-fsa',
      sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx',
    );
  }

  _ParsedFilename _parseNemoTransducer(String base) {
    // NeMo parakeet models support many European languages.
    // Languages are not in the filename; use supported set as approximation.
    return _ParsedFilename(
      type: 'asr',
      architecture: 'offlineNemoTransducer',
      languages: _supportedLanguages.toList()..sort(),
      origin: 'NVIDIA NeMo / k2-fsa',
      sourceUrl: 'https://github.com/NVIDIA/NeMo',
    );
  }

  List<String> _extractLanguagesFromFilename(String base) {
    final found = <String>[];
    // Match patterns like -en-, -de-kroko-, -fr-
    final matches = RegExp(r'-([a-z]{2})-').allMatches(base);
    for (final m in matches) {
      final lang = m.group(1)!;
      if (_supportedLanguages.contains(lang)) found.add(lang);
    }
    return found;
  }

  String _extractReleaseDate(String base) {
    // Look for YYYY-MM-DD pattern
    final dateMatch = RegExp(r'(\d{4})-(\d{2})-\d{2}').firstMatch(base);
    if (dateMatch != null) return '${dateMatch.group(1)}-${dateMatch.group(2)}';
    // Look for YYYY pattern
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
      'en': 'English', 'de': 'German', 'fr': 'French', 'es': 'Spanish',
      'it': 'Italian', 'nl': 'Dutch', 'pl': 'Polish', 'ru': 'Russian',
      'sv': 'Swedish', 'pt': 'Portuguese', 'cs': 'Czech',
    };
    return labels[code] ?? code.toUpperCase();
  }

  String _architectureLabel(String arch) {
    const labels = {
      'transducer': 'Zipformer', 'ctc': 'CTC', 'vitsPiper': 'Piper',
      'kokoro': 'Kokoro', 'onlineNemoCtc': 'NeMo CTC',
      'offlineNemoTransducer': 'Parakeet TDT',
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
