import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sherpa_voice/model_architecture.dart';

export 'package:sherpa_voice/model_architecture.dart';

/// A model available for download in the curated catalog.
class CatalogEntry {
  /// Unique identifier (used for storage and selection).
  final String id;

  /// Human-readable name shown in UI ("Language - Variant" format).
  final String displayName;

  /// ASR or TTS.
  final ModelType type;

  /// Language codes supported (ISO 639-1, e.g., 'en', 'de').
  final List<String> languages;

  /// Model architecture determines config construction.
  final ModelArchitecture architecture;

  /// Whether this ASR model supports streaming/live recognition.
  /// Always false for TTS models. Derived from [architecture] in fromJson.
  final bool supportsStreaming;

  /// Direct download URL for the .tar.bz2 archive.
  final String downloadUrl;

  /// Compressed download size in MB (shown to user before download).
  final double downloadSizeMb;

  /// Maps expected files within the extracted model directory.
  /// Keys are logical names, values are relative file paths.
  /// Example: {'encoder': 'encoder-epoch-99-avg-1.int8.onnx', 'tokens': 'tokens.txt'}
  final Map<String, String> fileStructure;

  /// Origin project or organization (e.g., "Next-gen Kaldi / k2-fsa").
  final String origin;

  /// URL to the upstream repository so users can verify licensing themselves.
  final String sourceUrl;

  /// Number of speaker voices (0 for ASR, 1 for single-speaker TTS, 54 for Kokoro).
  final int speakerCount;

  /// Release date in "YYYY-MM" format.
  final String releaseDate;

  /// Whether this is the recommended pick for its language+type combination.
  final bool recommended;

  const CatalogEntry({
    required this.id,
    required this.displayName,
    required this.type,
    required this.languages,
    required this.architecture,
    this.supportsStreaming = false,
    required this.downloadUrl,
    required this.downloadSizeMb,
    required this.fileStructure,
    required this.origin,
    required this.sourceUrl,
    this.speakerCount = 0,
    required this.releaseDate,
    this.recommended = false,
  });

  factory CatalogEntry.fromJson(Map<String, dynamic> json) {
    String require(String key) {
      final value = json[key] as String?;
      if (value == null) throw FormatException('Missing required field: $key');
      return value;
    }

    final typeStr = require('type');
    final type = ModelType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => throw FormatException('Unknown model type: $typeStr'),
    );

    final archStr = require('architecture');
    final architecture = ModelArchitecture.values.firstWhere(
      (e) => e.name == archStr,
      orElse: () => throw FormatException('Unknown architecture: $archStr'),
    );

    // Derived from architecture per spec: live architectures support streaming.
    final supportsStreaming = architecture == ModelArchitecture.transducer ||
        architecture == ModelArchitecture.ctc ||
        architecture == ModelArchitecture.onlineNemoCtc;

    final languagesRaw = json['languages'];
    if (languagesRaw == null) {
      throw const FormatException('Missing required field: languages');
    }
    final languages = List<String>.from(languagesRaw as List);

    final fileStructureRaw = json['fileStructure'];
    if (fileStructureRaw == null) {
      throw const FormatException('Missing required field: fileStructure');
    }
    final fileStructure = Map<String, String>.from(fileStructureRaw as Map);

    final downloadSizeMbRaw = json['downloadSizeMb'];
    if (downloadSizeMbRaw == null) {
      throw const FormatException('Missing required field: downloadSizeMb');
    }

    return CatalogEntry(
      id: require('id'),
      displayName: require('displayName'),
      type: type,
      languages: languages,
      architecture: architecture,
      supportsStreaming: supportsStreaming,
      downloadUrl: require('downloadUrl'),
      downloadSizeMb: (downloadSizeMbRaw as num).toDouble(),
      fileStructure: fileStructure,
      origin: require('origin'),
      sourceUrl: json['sourceUrl'] as String? ?? '',
      speakerCount: (json['speakerCount'] as int?) ?? 0,
      releaseDate: require('releaseDate'),
      recommended: (json['recommended'] as bool?) ?? false,
    );
  }
}

/// The curated model catalog, loaded from assets/voice-models.json at startup.
class ModelCatalog {
  static List<CatalogEntry> _entries = [];

  /// All approved catalog entries. Populated by [init] at app startup.
  static List<CatalogEntry> get entries => List.unmodifiable(_entries);

  /// Load and parse voice-models.json, caching only approved entries.
  ///
  /// Must be called once before any catalog queries. Accepts an optional
  /// [jsonOverride] string for testing without the Flutter asset bundle.
  static Future<void> init({String? jsonOverride}) async {
    final jsonString =
        jsonOverride ?? await rootBundle.loadString('assets/voice-models.json');
    final rawList = jsonDecode(jsonString) as List<dynamic>;
    _entries = rawList
        .cast<Map<String, dynamic>>()
        .where((e) {
          final status = e['status'] as String?;
          return status == 'approved';
        })
        .expand((e) {
          try {
            return [CatalogEntry.fromJson(e)];
          } catch (_) {
            return <CatalogEntry>[];
          }
        })
        .toList();
  }

  /// A wildcard sentinel for models supporting too many languages to
  /// enumerate (e.g. Omnilingual ASR's 1600) — matches any requested
  /// language code in [byLanguage]/[byTypeAndLanguage], and is excluded
  /// from [availableLanguages] since it isn't a real code a user picks.
  static const _multiLanguageSentinel = 'multi';

  /// All unique language codes in the catalog.
  static Set<String> get availableLanguages {
    final languages = <String>{};
    for (final entry in _entries) {
      languages.addAll(entry.languages);
    }
    languages.remove(_multiLanguageSentinel);
    return languages;
  }

  /// Get entries matching a language code, recommended entries first.
  static List<CatalogEntry> byLanguage(String languageCode) {
    return _entries
        .where((e) =>
            e.languages.contains(languageCode) ||
            e.languages.contains(_multiLanguageSentinel))
        .toList()
      ..sort(_recommendedFirst);
  }

  /// Get all entries of a specific type, recommended entries first.
  static List<CatalogEntry> byType(ModelType type) {
    return _entries.where((e) => e.type == type).toList()
      ..sort(_recommendedFirst);
  }

  /// Get entries matching a type and language, recommended entries first.
  static List<CatalogEntry> byTypeAndLanguage(
    ModelType type,
    String languageCode,
  ) {
    return _entries
        .where((e) =>
            e.type == type &&
            (e.languages.contains(languageCode) ||
                e.languages.contains(_multiLanguageSentinel)))
        .toList()
      ..sort(_recommendedFirst);
  }

  /// Find a catalog entry by its ID.
  static CatalogEntry? findById(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  static int _recommendedFirst(CatalogEntry a, CatalogEntry b) {
    if (a.recommended != b.recommended) return a.recommended ? -1 : 1;
    final nameCmp = a.displayName.compareTo(b.displayName);
    if (nameCmp != 0) return nameCmp;
    return a.id.compareTo(b.id);
  }
}

