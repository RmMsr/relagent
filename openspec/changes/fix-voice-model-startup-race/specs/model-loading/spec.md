## ADDED Requirements

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
