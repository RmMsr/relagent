## ADDED Requirements

### Requirement: Bundled Model Seeding
The app SHALL seed bundled model archives from Flutter assets into download storage on first launch so they are available as regular downloaded models without requiring a network download.

#### Scenario: Bundled archive extracted on first launch
- **WHEN** the app starts and a bundled `.tar.bz2` archive is found in `assets/voice-models/`
- **AND** no `.complete` marker exists at `getApplicationSupportDirectory()/models/<type>/<model-name>/`
- **THEN** the archive SHALL be extracted to that path using the same extraction logic as `ModelDownloadService`
- **AND** a `.complete` marker SHALL be written after successful extraction

#### Scenario: Already-seeded models are skipped
- **WHEN** the app starts and a `.complete` marker already exists for a bundled model
- **THEN** the seeding step SHALL skip that model without re-extracting

#### Scenario: Seeding completes before app UI renders
- **WHEN** the app initializes in `main.dart`
- **THEN** bundled model seeding SHALL complete before `runApp` is called
- **AND** the model list SHALL reflect seeded models as downloaded on first render

## MODIFIED Requirements

### Requirement: Asset-Based Model Loader
The system SHALL provide an `AssetModelLoader` that is used only during the seeding step to read archives from Flutter assets. It SHALL NOT be used as a runtime model loader after seeding is complete.

#### Scenario: Seeder reads archive from Flutter assets
- **WHEN** the bundled model seeder runs
- **THEN** it SHALL use asset-reading utilities to access the `.tar.bz2` archive bytes from `assets/voice-models/`
- **AND** SHALL NOT copy individual model files from assets to cache at runtime

#### Scenario: AssetModelLoader not used for inference
- **WHEN** ASR or TTS inference is requested
- **THEN** `AssetModelLoader` SHALL NOT be in the model loading path
- **AND** all model file access SHALL go through `DownloadModelLoader`

### Requirement: Model Loader Injection
The system SHALL inject `DownloadModelLoader` as the sole runtime loader into voice service implementations. `AssetModelLoader` is no longer injected into voice services.

#### Scenario: Native voice service receives download loader
- **WHEN** the native `VoiceService` is created
- **THEN** it SHALL receive a `DownloadModelLoader` instance
- **AND** it SHALL use the loader for all model file access

#### Scenario: Single loader code path
- **WHEN** a model file is needed for inference
- **THEN** only one code path SHALL exist regardless of whether the model was bundled or user-downloaded
- **AND** the path SHALL be via `DownloadModelLoader.loadModelFile`

## REMOVED Requirements

### Requirement: Asset-Based Model Loader (runtime loading)
**Reason**: Bundled models are now seeded into download storage on first launch. `AssetModelLoader` no longer serves as a runtime loader — its role as an on-demand asset copier is replaced by the one-time seeding step.
**Migration**: Bundled models are available via `DownloadModelLoader` after first launch. Code that previously injected `AssetModelLoader` should inject `DownloadModelLoader` instead.
