## ADDED Requirements

### Requirement: Startup Validation of Selected Models
On app startup, the system SHALL verify that selected ASR and TTS model IDs correspond to models that are actually available in download storage. Stale selections SHALL be cleared automatically.

#### Scenario: Selected ASR model still available
- **WHEN** the app starts
- **AND** the selected ASR model ID corresponds to a downloaded model
- **THEN** the selection SHALL be preserved unchanged

#### Scenario: Selected ASR model no longer available
- **WHEN** the app starts
- **AND** the selected ASR model ID does NOT correspond to a downloaded model
- **THEN** the ASR model selection SHALL be cleared to null
- **AND** the settings page SHALL show "None" for the active ASR model

#### Scenario: Selected TTS model no longer available
- **WHEN** the app starts
- **AND** the selected TTS model ID does NOT correspond to a downloaded model
- **THEN** the TTS model selection SHALL be cleared to null
- **AND** the settings page SHALL show "None" for the active TTS model

#### Scenario: No model selected at startup
- **WHEN** the app starts
- **AND** no ASR or TTS model is selected (both null)
- **THEN** no validation action SHALL be taken
- **AND** no errors SHALL be logged

#### Scenario: Validation runs after download scan completes
- **WHEN** the app starts
- **THEN** model validation SHALL occur after `ModelDownloadProvider` has completed its initial scan of download storage
- **AND** it SHALL NOT run while the scan is still in progress

## MODIFIED Requirements

### Requirement: Selected Model Persistence
The system SHALL persist the user's model selections in SharedPreferences.

#### Scenario: ASR model selection persists
- **GIVEN** the user has selected a downloaded ASR model
- **WHEN** the app is closed and reopened
- **THEN** the selected ASR model SHALL still be active

#### Scenario: TTS model selection persists
- **GIVEN** the user has selected a downloaded TTS model
- **WHEN** the app is closed and reopened
- **THEN** the selected TTS model SHALL still be active

#### Scenario: Selection cleared when model deleted
- **GIVEN** the user has selected a model that is subsequently deleted
- **WHEN** the app loads settings
- **THEN** the selection SHALL be cleared to null
- **AND** voice features SHALL be reported as unavailable until a new model is selected
