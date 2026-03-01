## ADDED Requirements

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

## MODIFIED Requirements

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
