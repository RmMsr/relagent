## Purpose

Define a shared pure Dart package `packages/sherpa_voice/` that encapsulates all sherpa-onnx-specific domain knowledge (architecture taxonomy, model loader interface, config builders, archive extractor) shared between the Flutter app and the voice-catalog CLI tool.

## Requirements

### Requirement: Shared sherpa-onnx Package
A pure Dart package `packages/sherpa_voice/` SHALL contain all sherpa-onnx-specific domain knowledge shared between the Flutter app and the voice-catalog CLI tool. It SHALL depend only on `sherpa_onnx`, `archive`, and `path` — no Flutter framework, no `path_provider`.

#### Scenario: Both consumers share identical config-building code
- **WHEN** the voice-catalog tool evaluates a model
- **THEN** it SHALL use the same config-building functions as the Flutter app
- **AND** a model that passes the smoke test SHALL be guaranteed to load in the app

#### Scenario: Package has no Flutter dependency
- **WHEN** `packages/sherpa_voice/pubspec.yaml` is inspected
- **THEN** it SHALL not declare `sdk: flutter` or depend on any Flutter plugin
- **AND** it SHALL be runnable with `dart run` without a Flutter engine

### Requirement: Architecture Taxonomy
`packages/sherpa_voice/` SHALL define the `ModelArchitecture` and `ModelType` enums as the single source of truth for the taxonomy of supported sherpa-onnx model types. Supported TTS architectures SHALL include `kokoro`, `vitsPiper`, and `pocket`. Supported ASR architectures SHALL include `transducer`, `ctc`, `onlineNemoCtc`, and `offlineNemoTransducer`.

#### Scenario: Both consumers import enums from the shared package
- **WHEN** `apps/` or `tools/voice_catalog/` references `ModelArchitecture`
- **THEN** the import SHALL resolve to `package:sherpa_voice/model_architecture.dart`
- **AND** no duplicate enum definitions SHALL exist elsewhere

### Requirement: Model Loader Interface in Shared Package
The `ModelLoader` abstract interface SHALL live in `packages/sherpa_voice/` so both the app and the tool can implement it independently with different storage strategies.

#### Scenario: App implements ModelLoader using path_provider
- **WHEN** the app loads a downloaded model
- **THEN** it SHALL use `DownloadModelLoader` which implements `ModelLoader` from `sherpa_voice`
- **AND** file paths SHALL be resolved via `getApplicationCacheDirectory()`

#### Scenario: Tool implements ModelLoader using a plain directory path
- **WHEN** the tool evaluates a model
- **THEN** it SHALL use a simple `ModelLoader` implementation that resolves paths from a known base directory
- **AND** it SHALL NOT use `path_provider`

### Requirement: ASR Config Builder
`packages/sherpa_voice/` SHALL expose a function that constructs an `OnlineRecognizer` given an architecture, a file-structure map, and a `ModelLoader`. The function SHALL handle all supported ASR architectures.

#### Scenario: Transducer config constructed correctly
- **WHEN** `buildAsrConfig` is called with `ModelArchitecture.transducer`
- **THEN** it SHALL build an `OnlineRecognizerConfig` with encoder, decoder, and joiner paths
- **AND** `modelType` SHALL be set to `'zipformer2'`

#### Scenario: CTC config constructed correctly
- **WHEN** `buildAsrConfig` is called with `ModelArchitecture.ctc`
- **THEN** it SHALL build an `OnlineRecognizerConfig` with a single model path via `zipformer2Ctc`
- **AND** `modelType` SHALL be set to `'zipformer2_ctc'`

#### Scenario: NeMo CTC config constructed correctly
- **WHEN** `buildAsrConfig` is called with `ModelArchitecture.onlineNemoCtc`
- **THEN** it SHALL build an `OnlineRecognizerConfig` with a single model path via `nemoCtc`
- **AND** `modelType` SHALL be set to `'nemo_ctc'`

#### Scenario: Unsupported architecture throws
- **WHEN** `buildAsrConfig` is called with an architecture not supported for online ASR
- **THEN** it SHALL throw `ArgumentError` naming the unsupported architecture

### Requirement: TTS Config Builder
`packages/sherpa_voice/` SHALL expose a function that constructs an `OfflineTts` given an architecture, a file-structure map, and a `ModelLoader`.

#### Scenario: Kokoro config constructed correctly
- **WHEN** `buildTtsConfig` is called with `ModelArchitecture.kokoro`
- **THEN** it SHALL build an `OfflineTtsConfig` with model, voices, tokens, and dataDir paths

#### Scenario: Piper config constructed correctly
- **WHEN** `buildTtsConfig` is called with `ModelArchitecture.vitsPiper`
- **THEN** it SHALL build an `OfflineTtsConfig` using the VITS config with model, tokens, and dataDir paths

#### Scenario: Pocket TTS config constructed correctly
- **WHEN** `buildTtsConfig` is called with `ModelArchitecture.pocket`
- **THEN** it SHALL build an `OfflineTtsConfig` using `OfflineTtsPocketModelConfig` with lmFlow, lmMain, encoder, decoder, textConditioner, vocabJson, and tokenScoresJson paths
- **AND** `voiceEmbeddingCacheCapacity` SHALL be set to enable voice embedding reuse across synthesis calls

#### Scenario: Kokoro multilingual config includes lexicon
- **WHEN** `buildTtsConfig` is called with `ModelArchitecture.kokoro` and `fileStructure` contains a `lexicon` key
- **THEN** the `lexicon` path SHALL be included in the `OfflineTtsKokoroModelConfig`
- **AND** models without a `lexicon` key SHALL receive an empty string for that field (monolingual Kokoro)

#### Scenario: Unsupported architecture throws
- **WHEN** `buildTtsConfig` is called with an architecture not supported for TTS
- **THEN** it SHALL throw `ArgumentError` naming the unsupported architecture

### Requirement: Archive Extractor
`packages/sherpa_voice/` SHALL provide a function that extracts a sherpa-onnx `.tar.bz2` archive to a destination directory, stripping the conventional top-level prefix.

#### Scenario: Top-level prefix is stripped
- **WHEN** an archive contains files prefixed with a single top-level directory name
- **THEN** the extractor SHALL strip that prefix so files land directly in `destDir`
- **AND** a `.complete` marker file SHALL be written after successful extraction

#### Scenario: Archive without top-level prefix extracts as-is
- **WHEN** an archive contains files without a shared top-level directory
- **THEN** files SHALL be extracted directly to `destDir` without path manipulation
