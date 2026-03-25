## REMOVED Requirements

### Requirement: Asset-Based Model Loader
**Reason**: Asset-bundled model loading is no longer used. No models are bundled via `config.json`. The download system is the sole model source.
**Migration**: All model loading uses `DownloadModelLoader`. Users must download models via the in-app model manager.

### Requirement: Model Loader Injection
**Reason**: With only `DownloadModelLoader` remaining, loaders are created per-model in `model_resolver.dart` rather than injected as a field into `NativeVoiceService`.
**Migration**: `NativeVoiceService` no longer holds a `ModelLoader` field. Model loaders are created on demand by the resolver.

## MODIFIED Requirements

### Requirement: Model Loader Resolution
The system SHALL select the appropriate `ModelLoader` implementation based on model availability.

#### Scenario: Downloaded model selected and available
- **WHEN** a user has selected a downloaded model in settings
- **AND** the model is available in download storage
- **THEN** the system SHALL use `DownloadModelLoader` for that model

#### Scenario: No model selected
- **WHEN** no downloaded model is selected in settings
- **THEN** the system SHALL report that voice features are unavailable
- **AND** it SHALL NOT attempt to create a recognizer or TTS instance

#### Scenario: Selected model not available in downloads
- **WHEN** a model ID is selected in settings but not present in download storage
- **THEN** the system SHALL report that voice features are unavailable
- **AND** it SHALL NOT attempt to create a recognizer or TTS instance

### Requirement: Lazy Initialization Resilience
Providers that initialize voice models SHALL handle the case where the model download scan has not yet completed at initialization time. When the selected model becomes available after initialization, the provider SHALL reinitialize with the correct model without requiring user action.

#### Scenario: ASR starts without model while scan is in progress
- **WHEN** `RecordingProvider.checkAutoStart()` is called
- **AND** `ModelDownloadState.downloadedModels` is still empty (scan in progress)
- **THEN** ASR SHALL NOT start recording
- **AND** when the selected model's download status transitions to downloaded, ASR SHALL start automatically

#### Scenario: TTS initializes before scan completes
- **WHEN** `TtsNotifier.initialize()` is called
- **AND** `ModelDownloadState.downloadedModels` is still empty (scan in progress)
- **THEN** TTS SHALL report unavailable
- **AND** when the selected model's download status transitions to downloaded, TTS SHALL reinitialize automatically

#### Scenario: TTS reinitialization deferred during active generation
- **WHEN** the selected TTS model becomes available in the download state
- **AND** a TTS generation task is currently in progress
- **THEN** reinitialization SHALL be deferred until all pending generation tasks complete
- **AND** the next generation request SHALL use the correct downloaded model

#### Scenario: ASR reinitializes when model becomes available during recording
- **WHEN** the selected ASR model's download status transitions to downloaded
- **AND** continuous recording is currently active
- **THEN** ASR recording SHALL stop and restart using the newly available model
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
