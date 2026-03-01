## ADDED Requirements

### Requirement: Model Archive Download
The system SHALL download model archives from remote URLs to a temporary location with progress tracking.

#### Scenario: Successful download with progress
- **WHEN** a model download is initiated with a valid URL
- **THEN** the system SHALL download the archive to a temporary file
- **AND** it SHALL report download progress as a percentage (bytes received / total bytes)
- **AND** the progress SHALL be observable by the UI

#### Scenario: Download size verification
- **WHEN** a download completes
- **THEN** the system SHALL verify the downloaded file size matches the expected size from the catalog
- **AND** it SHALL delete the temporary file and report an error if sizes do not match

#### Scenario: Download failure cleanup
- **WHEN** a download fails due to network error or cancellation
- **THEN** the system SHALL delete any partially downloaded temporary file
- **AND** it SHALL report the error to the caller

#### Scenario: Download cancellation
- **WHEN** the user cancels an in-progress download
- **THEN** the system SHALL abort the HTTP request
- **AND** it SHALL clean up the partial temporary file

### Requirement: Archive Extraction
The system SHALL extract downloaded `.tar.bz2` archives to the permanent model storage directory.

#### Scenario: Successful extraction
- **WHEN** a verified archive is ready for extraction
- **THEN** the system SHALL extract it to `<support_dir>/models/<type>/<model-name>/`
- **AND** it SHALL write a `.complete` marker file upon successful extraction
- **AND** it SHALL delete the temporary archive file

#### Scenario: Extraction to permanent storage
- **WHEN** a model is extracted
- **THEN** the target directory SHALL be under `getApplicationSupportDirectory()` (not cache)
- **AND** the model files SHALL persist across app updates and cache cleanup

#### Scenario: Partial extraction cleanup
- **WHEN** extraction fails or is interrupted
- **THEN** the system SHALL NOT write the `.complete` marker
- **AND** on next attempt, the system SHALL delete the incomplete directory and re-extract

### Requirement: Downloaded Model Management
The system SHALL track which models are downloaded and allow deletion of downloaded models.

#### Scenario: List downloaded models
- **WHEN** the system queries downloaded models
- **THEN** it SHALL scan the model storage directory for directories containing a `.complete` marker
- **AND** it SHALL return the list of model IDs that are fully downloaded

#### Scenario: Delete downloaded model
- **WHEN** the user requests deletion of a downloaded model
- **THEN** the system SHALL remove the model directory and all its contents
- **AND** if the deleted model was the active selection, the system SHALL clear the selection

#### Scenario: Storage space reporting
- **WHEN** the model management UI is displayed
- **THEN** the system SHALL report the total disk space used by downloaded models
