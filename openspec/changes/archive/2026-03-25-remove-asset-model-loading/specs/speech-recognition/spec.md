## MODIFIED Requirements

### Requirement: Dynamic ASR Model Selection
The ASR system SHALL use the model selected by the user rather than a hardcoded or bundled model name.

#### Scenario: Use user-selected downloaded model
- **WHEN** the user has selected a downloaded ASR model in settings
- **AND** the model is available in download storage
- **THEN** the recognizer factory SHALL load model files from the download storage directory
- **AND** it SHALL use the architecture specified in the model catalog entry

#### Scenario: No ASR model available
- **WHEN** no ASR model is selected in settings
- **THEN** the voice service SHALL report that speech recognition is unavailable
- **AND** the recording provider SHALL NOT attempt to start recording
- **AND** the UI SHALL indicate that a model download is required

#### Scenario: Selected ASR model not in downloads
- **WHEN** an ASR model ID is selected in settings but not present in download storage
- **THEN** the voice service SHALL treat this as "no model available"
- **AND** the recording provider SHALL NOT attempt to start recording

### Requirement: Lazy Initialization Resilience for ASR
The `RecordingProvider` SHALL handle the case where the selected ASR model is not yet available at initialization time. When the selected model becomes available after initial startup, the provider SHALL reinitialize ASR with the correct model without requiring user action.

#### Scenario: ASR waits for model when scan is in progress
- **WHEN** `RecordingProvider.checkAutoStart()` is called
- **AND** `ModelDownloadState.downloadedModels` is still empty (scan in progress)
- **THEN** ASR SHALL NOT start recording
- **AND** the system SHALL wait for the scan to complete before evaluating model availability

#### Scenario: ASR restarts when selected model becomes available during recording
- **WHEN** the selected ASR model's download status transitions to downloaded
- **AND** continuous recording is currently active
- **THEN** ASR recording SHALL stop and restart using the newly available model
- **AND** listening SHALL resume without user action

#### Scenario: No ASR restart when not recording
- **WHEN** the selected ASR model becomes available in the download state
- **AND** continuous recording is NOT currently active
- **THEN** the system SHALL NOT start recording
- **AND** the correct model SHALL be used when recording next starts

## REMOVED Requirements

### Requirement: Dynamic ASR Model Selection — bundled fallback scenario
**Reason**: Bundled models are removed. There is no asset-based fallback.
**Migration**: Users must download an ASR model via the in-app model manager. The UI communicates this requirement clearly.
