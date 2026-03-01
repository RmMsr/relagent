## MODIFIED Requirements

### Requirement: Lazy Initialization Resilience for ASR
The `RecordingProvider` SHALL handle the case where the selected ASR model is not yet available at initialization time. When the selected model becomes available after initial startup, the provider SHALL reinitialize ASR with the correct model without requiring user action.

#### Scenario: ASR starts with bundled model while scan is in progress
- **WHEN** `RecordingProvider.checkAutoStart()` is called
- **AND** `ModelDownloadState.downloadedModels` is still empty (scan in progress)
- **THEN** ASR SHALL start using the bundled model as fallback
- **AND** recording SHALL function normally with the bundled model

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
