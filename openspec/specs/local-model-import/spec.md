## Purpose

Allow users to import sherpa-onnx model archives from local device storage directly into the app, bypassing the curated catalog. Imported models are stored persistently in the application support directory and appear first in the catalog browser.

## Requirements

### Requirement: File Selection via System Picker
The system SHALL allow the user to select a model archive from device storage using the platform's native file picker. Supported formats are `.tar.bz2`, `.tar.gz`, `.tgz`, `.zip`, and plain `.tar`. The correct format is detected from magic bytes, not the file extension.

#### Scenario: User opens file picker
- **WHEN** the user taps the "Import from storage" action in the catalog browser
- **THEN** the system file picker SHALL open filtered to supported archive formats

#### Scenario: User cancels picker
- **WHEN** the user dismisses the file picker without selecting a file
- **THEN** no import flow SHALL be initiated
- **AND** the catalog browser SHALL remain unchanged

#### Scenario: File selected
- **WHEN** the user selects a supported archive file
- **THEN** the system SHALL proceed to architecture detection and show the metadata form

#### Scenario: Loading indicator during archive peek
- **WHEN** the selected archive is being read to detect its contents
- **THEN** a loading indicator SHALL be visible on the import action button

### Requirement: Architecture Auto-Detection
The system SHALL inspect the file names within a selected archive and attempt to determine the model architecture before presenting the metadata form.

#### Scenario: Transducer detected
- **WHEN** the archive contains files matching `encoder*.onnx`, `decoder*.onnx`, and `joiner*.onnx`
- **THEN** the detected architecture SHALL be `transducer`
- **AND** the architecture field in the metadata form SHALL be pre-filled with this value

#### Scenario: NeMo CTC streaming detected
- **WHEN** the archive contains a single model `.onnx` file and `tokens.txt`, and any entry path contains "nemo"
- **THEN** the detected architecture SHALL be `onlineNemoCtc`

#### Scenario: CTC detected
- **WHEN** the archive contains a single model `.onnx` file and `tokens.txt` with no "nemo" indicator
- **THEN** the detected architecture SHALL be `ctc`

#### Scenario: Piper VITS detected
- **WHEN** the archive contains a model `.onnx` file and an `espeak-ng-data/` directory entry
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

#### Scenario: Model type pre-selected from active tab
- **WHEN** the metadata form is shown
- **THEN** the model type (ASR or TTS) SHALL default to whichever tab was active in the catalog browser

#### Scenario: Architecture dropdown filtered by model type
- **WHEN** the model type toggle is changed
- **THEN** the architecture dropdown SHALL show only architectures compatible with the selected type
- **AND** if the previously selected architecture is incompatible it SHALL be cleared

#### Scenario: Architecture mismatch warning
- **WHEN** the user selects an architecture that differs from the auto-detected architecture
- **THEN** a warning SHALL be shown explaining that the wrong architecture will crash the app

#### Scenario: Architecture is required
- **WHEN** the user attempts to confirm the import
- **AND** no architecture is selected
- **THEN** the form SHALL prevent confirmation

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

### Requirement: Metadata Editing
The user SHALL be able to edit the metadata (display name, type, architecture, languages) of an already-imported model without re-importing.

#### Scenario: Edit action opens pre-filled form
- **WHEN** the user activates the edit action on an imported model card
- **THEN** the metadata form SHALL open pre-filled with the model's current values

#### Scenario: Edit preserves model files and ID
- **WHEN** the user confirms edited metadata
- **THEN** only the manifest entry SHALL be updated
- **AND** the model files on disk SHALL remain untouched
- **AND** the model ID SHALL be unchanged

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
- **WHEN** `imported_models.json` does not exist
- **THEN** the imported model registry SHALL initialise with an empty list

#### Scenario: Imported model ID is unique and stable
- **WHEN** a model is imported
- **THEN** it SHALL be assigned an ID of the form `imported-<random>` that does not change after import

### Requirement: Imported Model Loader
The system SHALL be able to load imported models using the same `ModelLoader` interface used by downloaded catalog models.

#### Scenario: ASR model resolves to correct directory
- **WHEN** an imported ASR model is selected and the engine requests its files
- **THEN** the loader SHALL resolve paths relative to `<support_dir>/imported_models/asr/<id>/`
- **AND** the file structure SHALL be inferred by scanning the directory

#### Scenario: TTS model resolves to correct directory
- **WHEN** an imported TTS model is selected and the engine requests its files
- **THEN** the loader SHALL resolve paths relative to `<support_dir>/imported_models/tts/<id>/`

#### Scenario: TTS model paths validated before engine init
- **WHEN** a TTS imported model is about to be initialised
- **THEN** required files for its architecture SHALL be verified to exist
- **AND** if any required file is missing the system SHALL surface a user-visible error instead of crashing

#### Scenario: Loader reports unavailability when .complete marker is absent
- **WHEN** the `.complete` marker is missing from the model directory
- **THEN** `isModelAvailable` SHALL return `false`

### Requirement: TTS Crash Recovery
Because certain model format mismatches cause an unrecoverable native crash (SIGABRT), the system SHALL detect and recover from such crashes automatically.

#### Scenario: Crash guard set before TTS init
- **WHEN** TTS initialisation is about to begin for a model
- **THEN** the model ID SHALL be persisted to stable storage as a crash guard

#### Scenario: Crash guard cleared on success
- **WHEN** TTS initialisation completes without error
- **THEN** the crash guard SHALL be cleared

#### Scenario: Crashed model auto-deselected on restart
- **WHEN** the app starts and the crash guard key is present
- **THEN** the guarded model SHALL be deselected
- **AND** the user SHALL see an error message explaining that the model was deselected due to a crash

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
