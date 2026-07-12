## ADDED Requirements

### Requirement: File Selection via System Picker
The system SHALL allow the user to select a `.tar.bz2` model archive from device storage using the platform's native file picker.

#### Scenario: User opens file picker
- **WHEN** the user taps the "Import from storage" action in the catalog browser
- **THEN** the system file picker SHALL open filtered to `.tar.bz2` files

#### Scenario: User cancels picker
- **WHEN** the user dismisses the file picker without selecting a file
- **THEN** no import flow SHALL be initiated
- **AND** the catalog browser SHALL remain unchanged

#### Scenario: File selected
- **WHEN** the user selects a `.tar.bz2` file
- **THEN** the system SHALL proceed to architecture detection and show the metadata form

### Requirement: Architecture Auto-Detection
The system SHALL inspect the file names within a selected archive and attempt to determine the model architecture before presenting the metadata form.

#### Scenario: Transducer detected
- **WHEN** the archive contains files matching `encoder*.onnx`, `decoder*.onnx`, and `joiner*.onnx`
- **THEN** the detected architecture SHALL be `transducer`
- **AND** the architecture field in the metadata form SHALL be pre-filled with this value

#### Scenario: CTC detected
- **WHEN** the archive contains `model.onnx` and `tokens.txt` and the type is ASR
- **THEN** the detected architecture SHALL be `ctc`

#### Scenario: Piper VITS detected
- **WHEN** the archive contains `model.onnx` and an `espeak-ng-data/` directory entry
- **THEN** the detected architecture SHALL be `vitsPiper`

#### Scenario: Kokoro detected
- **WHEN** the archive contains `voices.bin`
- **THEN** the detected architecture SHALL be `kokoro`

#### Scenario: Detection fails
- **WHEN** no known file pattern is matched
- **THEN** the architecture field SHALL be left blank and marked as required in the metadata form

### Requirement: Metadata Form
After a file is selected, the system SHALL present a form where the user can supply or confirm metadata before the import is finalised.

#### Scenario: Form pre-fills display name from filename
- **WHEN** the metadata form is shown
- **THEN** the display name field SHALL be pre-filled with the archive filename stripped of its extension

#### Scenario: Model type is required
- **WHEN** the user attempts to confirm the import
- **AND** no model type (ASR or TTS) has been selected
- **THEN** the form SHALL show a validation error and SHALL NOT proceed

#### Scenario: Architecture is required
- **WHEN** the user attempts to confirm the import
- **AND** no architecture is selected
- **THEN** the form SHALL show a validation error and SHALL NOT proceed

#### Scenario: Language is optional
- **WHEN** the user confirms the import without entering any language codes
- **THEN** the import SHALL proceed with an empty language list

#### Scenario: Display name is optional
- **WHEN** the user confirms the import with an empty display name field
- **THEN** the archive filename (without extension) SHALL be used as the display name

#### Scenario: User cancels form
- **WHEN** the user dismisses the metadata form
- **THEN** no model SHALL be imported
- **AND** no files SHALL be written to storage

### Requirement: Archive Extraction to Support Directory
The system SHALL extract the selected archive to a persistent location under the application support directory.

#### Scenario: Archive extracted to typed sub-path
- **WHEN** the user confirms the import with model type ASR
- **THEN** the archive SHALL be extracted to `<support_dir>/imported_models/asr/<id>/`
- **AND** a `.complete` marker file SHALL be written after successful extraction

#### Scenario: TTS model stored under tts sub-path
- **WHEN** the user confirms the import with model type TTS
- **THEN** the archive SHALL be extracted to `<support_dir>/imported_models/tts/<id>/`

#### Scenario: Extraction failure leaves no partial state
- **WHEN** archive extraction fails (e.g., corrupt archive, out of space)
- **THEN** any partially written files SHALL be cleaned up
- **AND** the user SHALL see an error message
- **AND** no entry SHALL be added to the imported models manifest

#### Scenario: Extraction runs off the main thread
- **WHEN** the archive is being extracted
- **THEN** the UI SHALL remain responsive
- **AND** a progress indicator SHALL be visible

### Requirement: Imported Model Registry
The system SHALL maintain a JSON manifest of all imported models at `<support_dir>/imported_models.json` and load it at app startup.

#### Scenario: Manifest updated after successful import
- **WHEN** an import completes successfully
- **THEN** an entry SHALL be appended to `imported_models.json` with the fields: `id`, `displayName`, `type`, `architecture`, `languages`, `importedAt`

#### Scenario: Manifest loaded at startup
- **WHEN** the app starts
- **THEN** all entries in `imported_models.json` SHALL be loaded into the imported model registry
- **AND** shall be available for model selection

#### Scenario: Missing manifest is not an error
- **WHEN** `imported_models.json` does not exist (e.g., no models have been imported yet)
- **THEN** the imported model registry SHALL initialise with an empty list

#### Scenario: Imported model ID is unique and stable
- **WHEN** a model is imported
- **THEN** it SHALL be assigned an ID of the form `imported-<uuid>` that does not change after import

### Requirement: Imported Model Loader
The system SHALL be able to load imported models using the same `ModelLoader` interface used by downloaded catalog models.

#### Scenario: ASR model resolves to correct directory
- **WHEN** an imported ASR model is selected and the engine requests its files
- **THEN** the loader SHALL resolve paths relative to `<support_dir>/imported_models/asr/<id>/`

#### Scenario: TTS model resolves to correct directory
- **WHEN** an imported TTS model is selected and the engine requests its files
- **THEN** the loader SHALL resolve paths relative to `<support_dir>/imported_models/tts/<id>/`

#### Scenario: Loader reports unavailability when .complete marker is absent
- **WHEN** the `.complete` marker is missing from the model directory
- **THEN** `isModelAvailable` SHALL return `false`

### Requirement: Imported Model Deletion
The user SHALL be able to delete an imported model from within the app.

#### Scenario: Delete removes files and manifest entry
- **WHEN** the user confirms deletion of an imported model
- **THEN** the directory `<support_dir>/imported_models/<type>/<id>/` SHALL be deleted
- **AND** the corresponding entry SHALL be removed from `imported_models.json`
- **AND** the model SHALL no longer appear in any model listing

#### Scenario: Deleting the active model clears the selection
- **WHEN** the user deletes a model that is currently selected as the active ASR or TTS model
- **THEN** the corresponding selection SHALL be cleared in settings
