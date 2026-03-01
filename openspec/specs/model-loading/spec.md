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
