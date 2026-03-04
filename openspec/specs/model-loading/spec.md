## Purpose

Define a unified `ModelLoader` interface that abstracts model loading from different sources (bundled assets, downloads), enabling flexible model management and dependency injection.

## Requirements

### Requirement: Model Loader Interface
The system SHALL define an abstract `ModelLoader` interface that decouples model access from the specific loading strategy (asset bundling, file download, etc.).

#### Scenario: Interface provides model file loading
- **WHEN** a consumer needs access to a model file
- **THEN** it SHALL call `ModelLoader.loadModelFile(modelName, fileName)`
- **AND** the method SHALL return the file system path to the loaded file

#### Scenario: Interface provides model directory loading
- **WHEN** a consumer needs access to a model directory (e.g., espeak-ng-data)
- **THEN** it SHALL call `ModelLoader.loadModel(modelName)`
- **AND** the method SHALL return the file system path to the model directory

#### Scenario: Interface supports checking model availability
- **WHEN** a consumer needs to know if a model is available before loading
- **THEN** it SHALL call `ModelLoader.isModelAvailable(modelName)`
- **AND** the method SHALL return true if the model files exist and are complete

### Requirement: Asset-Based Model Loader
The system SHALL provide an `AssetModelLoader` implementation that loads models from bundled Flutter assets by copying them to the application cache directory.

#### Scenario: First load copies from assets to cache
- **WHEN** a model file is requested for the first time
- **THEN** the loader SHALL copy the file from Flutter assets to the cache directory
- **AND** the returned path SHALL point to the cached copy

#### Scenario: Subsequent loads use cached copy
- **WHEN** a model file has already been copied to cache
- **THEN** the loader SHALL return the cached path without re-copying
- **AND** file integrity SHALL be verified (non-zero size)

#### Scenario: Directory copying preserves structure
- **WHEN** a model directory is requested
- **THEN** all files within the asset directory SHALL be copied to cache preserving the directory structure
- **AND** a marker file SHALL indicate successful copy completion

### Requirement: Unavailable Model Loader for Web
The system SHALL provide an `UnavailableModelLoader` implementation for platforms that cannot load local models.

#### Scenario: Web model loader throws on access
- **WHEN** `loadModelFile` or `loadModel` is called on web
- **THEN** the loader SHALL throw `UnsupportedError`
- **AND** callers SHALL handle this gracefully (voice service stub never calls the loader)

### Requirement: Model Loader Injection
The system SHALL inject the `ModelLoader` into voice service implementations rather than having them access file utilities directly.

#### Scenario: Native voice service receives asset loader
- **WHEN** the native `VoiceService` is created
- **THEN** it SHALL receive an `AssetModelLoader` instance
- **AND** it SHALL use the loader for all model file access instead of calling `copyAssetFileToCache` directly

#### Scenario: No dart:io outside model loader
- **WHEN** model files need to be accessed
- **THEN** only the `AssetModelLoader` implementation SHALL import `dart:io`
- **AND** no other code in the app SHALL use `dart:io` for model loading

### Requirement: Download-Based Model Loader
The system SHALL provide a `DownloadModelLoader` implementation of `ModelLoader` that loads models from the permanent download storage directory.

#### Scenario: Load model file from download storage
- **WHEN** `loadModelFile(modelName, fileName)` is called
- **THEN** it SHALL return the path `<support_dir>/models/<type>/<modelName>/<fileName>`
- **AND** it SHALL verify the file exists before returning

#### Scenario: Load model directory from download storage
- **WHEN** `loadModelDirectory(modelName, dirName)` is called
- **THEN** it SHALL return the path `<support_dir>/models/<type>/<modelName>/<dirName>`
- **AND** it SHALL verify the directory exists before returning

#### Scenario: File not found in download storage
- **WHEN** a requested model file does not exist in download storage
- **THEN** the loader SHALL throw a descriptive error indicating the model needs to be downloaded

### Requirement: Model Loader Resolution
The system SHALL select the appropriate `ModelLoader` implementation based on model availability.

#### Scenario: Downloaded model takes priority
- **WHEN** a user has selected a downloaded model in settings
- **THEN** the system SHALL use `DownloadModelLoader` for that model

#### Scenario: Asset fallback when no download selected
- **WHEN** no downloaded model is selected and bundled assets are available
- **THEN** the system SHALL fall back to `AssetModelLoader`

#### Scenario: No models available
- **WHEN** no downloaded model is selected and no bundled assets are available
- **THEN** the system SHALL report that voice features are unavailable
- **AND** it SHALL NOT attempt to create a recognizer or TTS instance

### Requirement: Lazy Initialization Resilience
Providers that initialize voice models SHALL handle the case where the model download scan has not yet completed at initialization time. When the selected model becomes available after initialization, the provider SHALL reinitialize with the correct model without requiring user action.

#### Scenario: TTS initializes before scan completes
- **WHEN** `TtsNotifier.initialize()` is called
- **AND** `ModelDownloadState.downloadedModels` is still empty (scan in progress)
- **THEN** TTS SHALL initialize using the bundled model as fallback
- **AND** when the selected model's download status transitions to downloaded, TTS SHALL reinitialize automatically

#### Scenario: TTS reinitialization deferred during active generation
- **WHEN** the selected TTS model becomes available in the download state
- **AND** a TTS generation task is currently in progress
- **THEN** reinitialization SHALL be deferred until all pending generation tasks complete
- **AND** the next generation request SHALL use the correct downloaded model

#### Scenario: ASR reinitializes when model becomes available
- **WHEN** the selected ASR model becomes available in the download state
- **AND** continuous recording is currently active
- **THEN** the ASR recording SHALL stop and restart using the newly available model
- **AND** listening SHALL resume without user action

#### Scenario: No spurious ASR restart when not recording
- **WHEN** the selected ASR model becomes available in the download state
- **AND** continuous recording is NOT currently active
- **THEN** the system SHALL NOT start recording
- **AND** the correct model SHALL be used when recording next starts

### Requirement: JSON-Driven Model Catalog
The `ModelCatalog` class SHALL load its entries from `assets/voice-models.json` at app startup rather than declaring them as compile-time constants. The public query API (`entries`, `byType`, `byLanguage`, `byTypeAndLanguage`, `findById`, `availableLanguages`) SHALL remain unchanged so that no other code requires modification.

#### Scenario: Catalog initialised from asset on first access
- **WHEN** any `ModelCatalog` query method is called for the first time
- **THEN** `ModelCatalog` SHALL have already parsed `voice-models.json` via `rootBundle`
- **AND** the returned entries SHALL match only those with `status == "approved"` in the JSON

#### Scenario: Catalog is initialised once at app startup
- **WHEN** the app launches
- **THEN** `voice-models.json` SHALL be parsed exactly once and cached in memory
- **AND** subsequent calls to `ModelCatalog` query methods SHALL use the in-memory cache

#### Scenario: Catalog query API is unchanged
- **WHEN** existing code calls `ModelCatalog.byType(ModelType.asr)`
- **THEN** it SHALL receive a `List<CatalogEntry>` with the same shape as before
- **AND** no call sites outside `model_catalog.dart` SHALL require changes

### Requirement: CatalogEntry JSON Deserialisation
`CatalogEntry` SHALL gain a `fromJson` factory constructor that parses a JSON object into a typed `CatalogEntry` instance, mapping the JSON field names defined in the `voice-model-index` spec to the existing Dart fields.

#### Scenario: Valid entry deserialises without error
- **WHEN** `CatalogEntry.fromJson` is called with a complete, valid JSON object
- **THEN** it SHALL return a `CatalogEntry` with all fields populated correctly
- **AND** enum fields (`type`, `architecture`) SHALL be parsed from their string representations

#### Scenario: Missing required field throws descriptive error
- **WHEN** `CatalogEntry.fromJson` is called with a JSON object that omits a required field
- **THEN** it SHALL throw a `FormatException` naming the missing field
- **AND** the app SHALL surface this as a startup error rather than a null-safety crash

#### Scenario: Unknown architecture string is handled
- **WHEN** `CatalogEntry.fromJson` encounters an `architecture` value not in `ModelArchitecture`
- **THEN** it SHALL throw a `FormatException` with the unrecognised value
- **AND** the catalog SHALL not load partially (all-or-nothing parse)

### Requirement: Recommended Entries Exposed
`ModelCatalog` SHALL expose the `recommended` flag from each entry so that the model selection UI can sort and highlight entries appropriately.

#### Scenario: Recommended flag available on CatalogEntry
- **WHEN** code reads `entry.recommended`
- **THEN** it SHALL return `true` for entries marked `recommended: true` in the JSON
- **AND** `false` for all other approved entries

#### Scenario: Recommended entries sort before non-recommended
- **WHEN** `ModelCatalog.byType` or `ModelCatalog.byTypeAndLanguage` returns a list
- **THEN** entries with `recommended == true` SHALL appear first in the list
