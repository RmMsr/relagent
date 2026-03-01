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
  /// Always false for TTS models.
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

  /// License identifier (e.g., "Apache-2.0", "MIT").
  final String license;

  /// Number of speaker voices (0 for ASR, 1 for single-speaker TTS, 54 for Kokoro).
  final int speakerCount;

  /// Release date in "YYYY-MM" format.
  final String releaseDate;

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
    required this.license,
    this.speakerCount = 0,
    required this.releaseDate,
  });
}

/// Architecture/engine of the model, determines how to configure sherpa-onnx.
enum ModelArchitecture {
  /// Zipformer transducer: encoder + decoder + joiner
  transducer,

  /// CTC: encoder only (e.g., omnilingual model)
  ctc,

  /// Piper VITS: model.onnx + tokens.txt + espeak-ng-data
  vitsPiper,

  /// Kokoro: model.onnx + voices.bin + tokens.txt + espeak-ng-data
  kokoro,

  /// Nemo CTC: model.onnx + tokens.txt
  onlineNemoCtc,

  /// NeMo offline transducer: encoder + decoder + joiner (VAD-simulated streaming)
  offlineNemoTransducer,
}

/// The curated model catalog.
class ModelCatalog {
  static const _ghRelease =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download';

  // Entries sorted alphabetically by displayName within each type.
  static const List<CatalogEntry> entries = [
    // --- ASR Models (alphabetical) ---
    CatalogEntry(
      id: 'zipformer-en-kroko',
      displayName: 'English - Zipformer',
      type: ModelType.asr,
      languages: ['en'],
      architecture: ModelArchitecture.transducer,
      supportsStreaming: true,
      downloadUrl:
          '$_ghRelease/asr-models/sherpa-onnx-streaming-zipformer-en-kroko-2025-08-06.tar.bz2',
      downloadSizeMb: 55,
      fileStructure: {
        'encoder': 'encoder.onnx',
        'decoder': 'decoder.onnx',
        'joiner': 'joiner.onnx',
        'tokens': 'tokens.txt',
      },
      origin: 'Next-gen Kaldi / k2-fsa',
      license: 'Apache-2.0',
      releaseDate: '2025-08',
    ),

    CatalogEntry(
      id: 'zipformer-fr-kroko',
      displayName: 'French - Zipformer',
      type: ModelType.asr,
      languages: ['fr'],
      architecture: ModelArchitecture.transducer,
      supportsStreaming: true,
      downloadUrl:
          '$_ghRelease/asr-models/sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06.tar.bz2',
      downloadSizeMb: 55,
      fileStructure: {
        'encoder': 'encoder.onnx',
        'decoder': 'decoder.onnx',
        'joiner': 'joiner.onnx',
        'tokens': 'tokens.txt',
      },
      origin: 'Next-gen Kaldi / k2-fsa',
      license: 'Apache-2.0',
      releaseDate: '2025-08',
    ),

    CatalogEntry(
      id: 'zipformer-de-kroko',
      displayName: 'German - Zipformer',
      type: ModelType.asr,
      languages: ['de'],
      architecture: ModelArchitecture.transducer,
      supportsStreaming: true,
      downloadUrl:
          '$_ghRelease/asr-models/sherpa-onnx-streaming-zipformer-de-kroko-2025-08-06.tar.bz2',
      downloadSizeMb: 55,
      fileStructure: {
        'encoder': 'encoder.onnx',
        'decoder': 'decoder.onnx',
        'joiner': 'joiner.onnx',
        'tokens': 'tokens.txt',
      },
      origin: 'Next-gen Kaldi / k2-fsa',
      license: 'Apache-2.0',
      releaseDate: '2025-08',
    ),

    CatalogEntry(
      id: 'nemo-parakeet-tdt-0.6b-v3-int8',
      displayName: 'Multilingual - Parakeet TDT (25 languages)',
      type: ModelType.asr,
      languages: [
        'bg',
        'hr',
        'cs',
        'da',
        'nl',
        'en',
        'et',
        'fi',
        'fr',
        'de',
        'el',
        'hu',
        'it',
        'lv',
        'lt',
        'mt',
        'pl',
        'pt',
        'ro',
        'sk',
        'sl',
        'es',
        'sv',
        'ru',
        'uk',
      ],
      architecture: ModelArchitecture.offlineNemoTransducer,
      supportsStreaming: true,
      downloadUrl:
          '$_ghRelease/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2',
      downloadSizeMb: 465,
      fileStructure: {
        'encoder': 'encoder.int8.onnx',
        'decoder': 'decoder.int8.onnx',
        'joiner': 'joiner.int8.onnx',
        'tokens': 'tokens.txt',
      },
      origin: 'NVIDIA NeMo / k2-fsa',
      license: 'Apache-2.0',
      releaseDate: '2025-08',
    ),

    // Omnilingual CTC model (omnilingual-ctc-v2-int8) removed:
    // This is an offline-only model (no streaming support). Our app uses
    // OnlineRecognizer for real-time streaming ASR. The model crashes with
    // "'encoder_dims' does not exist in the metadata" because it's not a
    // zipformer2 CTC model. Re-add when offline ASR support is implemented.

    // --- TTS Models (alphabetical) ---
    CatalogEntry(
      id: 'kokoro-en-v0_19-int8',
      displayName: 'English - Kokoro',
      type: ModelType.tts,
      languages: ['en'],
      architecture: ModelArchitecture.kokoro,
      downloadUrl: '$_ghRelease/tts-models/kokoro-int8-en-v0_19.tar.bz2',
      downloadSizeMb: 99,
      fileStructure: {
        'model': 'model.int8.onnx',
        'voices': 'voices.bin',
        'tokens': 'tokens.txt',
        'dataDir': 'espeak-ng-data',
      },
      origin: 'Kokoro / Hexgrad',
      license: 'Apache-2.0',
      speakerCount: 54,
      releaseDate: '2025-01',
    ),

    CatalogEntry(
      id: 'piper-en-lessac-medium-int8',
      displayName: 'English - Lessac',
      type: ModelType.tts,
      languages: ['en'],
      architecture: ModelArchitecture.vitsPiper,
      downloadUrl:
          '$_ghRelease/tts-models/vits-piper-en_US-lessac-medium-int8.tar.bz2',
      downloadSizeMb: 20,
      fileStructure: {
        'model': 'en_US-lessac-medium.onnx',
        'tokens': 'tokens.txt',
        'dataDir': 'espeak-ng-data',
      },
      origin: 'Piper / Rhasspy',
      license: 'MIT',
      speakerCount: 1,
      releaseDate: '2024-06',
    ),

    // tts-models/vits-piper-fr_FR-siwis-medium-int8.tar.bz2 removed because it crashes
    // tts-models/vits-piper-fr_FR-tom-medium-int8.tar.bz2 removed because it crashes
    CatalogEntry(
      id: 'piper-de-thorsten-medium-int8',
      displayName: 'German - Thorsten',
      type: ModelType.tts,
      languages: ['de'],
      architecture: ModelArchitecture.vitsPiper,
      downloadUrl:
          '$_ghRelease/tts-models/vits-piper-de_DE-thorsten-medium-int8.tar.bz2',
      downloadSizeMb: 20,
      fileStructure: {
        'model': 'de_DE-thorsten-medium.onnx',
        'tokens': 'tokens.txt',
        'dataDir': 'espeak-ng-data',
      },
      origin: 'Piper / Rhasspy',
      license: 'MIT',
      speakerCount: 1,
      releaseDate: '2024-06',
    ),

    // Norwegian Piper model (piper-no-talesyntese-medium-int8) removed:
    // Crashes with "Failed to set eSpeak-ng voice" during audio generation.
    // The eSpeak-ng library bundled in sherpa-onnx 1.12.25 does not support
    // the Norwegian Bokmal voice code "nb". Re-add when sherpa-onnx fixes this.

    // vits-piper-ru_RU-dmitri-medium-int8.tar.bz2 removed because it crashes
    // vits-piper-ru_RU-irina-medium-int8.tar.bz2 removed because it crashes
    // vits-piper-sv_SE-nst-medium-int8.tar.bz2 removed because it crashes
  ];

  /// All unique language codes in the catalog.
  static Set<String> get availableLanguages {
    final languages = <String>{};
    for (final entry in entries) {
      languages.addAll(entry.languages);
    }
    return languages;
  }

  /// Get entries matching a language code.
  static List<CatalogEntry> byLanguage(String languageCode) {
    return entries.where((e) => e.languages.contains(languageCode)).toList();
  }

  /// Get all entries of a specific type.
  static List<CatalogEntry> byType(ModelType type) {
    return entries.where((e) => e.type == type).toList();
  }

  /// Get entries matching a type and language.
  static List<CatalogEntry> byTypeAndLanguage(
    ModelType type,
    String languageCode,
  ) {
    return entries
        .where((e) => e.type == type && e.languages.contains(languageCode))
        .toList();
  }

  /// Find a catalog entry by its ID.
  static CatalogEntry? findById(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}

/// Type of voice model.
enum ModelType { asr, tts }
