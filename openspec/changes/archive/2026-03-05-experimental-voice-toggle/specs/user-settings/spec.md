## ADDED Requirements

### Requirement: Continuous voice enabled setting

The system SHALL persist a `continuousVoiceEnabled` boolean in the Settings model, defaulting to `false`.

#### Scenario: continuousVoiceEnabled defaults to false
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** settings are loaded
- **THEN** `continuousVoiceEnabled` SHALL be `false`

#### Scenario: continuousVoiceEnabled persists across restarts
- **GIVEN** the user has enabled continuous voice mode
- **WHEN** the app is closed and reopened
- **THEN** `continuousVoiceEnabled` SHALL still be `true`

#### Scenario: continuousVoiceEnabled serialized in JSON
- **GIVEN** settings are serialized for persistence
- **WHEN** the JSON representation is written to SharedPreferences
- **THEN** `continuousVoiceEnabled` SHALL be included as a boolean field

#### Scenario: Migration from settings without continuousVoiceEnabled
- **GIVEN** persisted settings JSON does not contain `continuousVoiceEnabled`
- **WHEN** settings are deserialized
- **THEN** `continuousVoiceEnabled` SHALL default to `false`

### Requirement: Voice mode enforcement based on continuous voice toggle

The system SHALL prevent activation of continuous voice modes (`listening`, `conversation`) when `continuousVoiceEnabled` is `false`.

#### Scenario: Reject continuous mode when toggle is off
- **GIVEN** `continuousVoiceEnabled` is `false`
- **WHEN** `updateVoiceMode()` is called with `VoiceMode.listening` or `VoiceMode.conversation`
- **THEN** the voice mode SHALL NOT be changed
- **AND** it SHALL remain at the current mode

#### Scenario: Clamp voice mode when toggle is disabled
- **GIVEN** `continuousVoiceEnabled` is `true`
- **AND** the current voice mode is `listening` or `conversation`
- **WHEN** `continuousVoiceEnabled` is set to `false`
- **THEN** the voice mode SHALL be changed to `silent`

#### Scenario: Allow continuous modes when toggle is on
- **GIVEN** `continuousVoiceEnabled` is `true`
- **WHEN** `updateVoiceMode()` is called with `VoiceMode.listening` or `VoiceMode.conversation`
- **THEN** the voice mode SHALL be updated accordingly

## MODIFIED Requirements

### Requirement: Voice settings visible when available
The voice-related settings sections SHALL be conditionally visible based on platform voice capabilities and model availability. The settings page SHALL use a tabbed layout with voice settings on a dedicated "Voice" tab.

#### Scenario: Voice settings visible when available
- **GIVEN** the user opens the settings page on a platform with voice capabilities
- **WHEN** the user navigates to the Voice tab
- **THEN** voice model management (ASR and TTS) SHALL be displayed
- **AND** TTS-related settings (speaker, speed) SHALL be displayed

#### Scenario: Voice mode selector indicates model requirement
- **GIVEN** no ASR model is available (neither bundled nor downloaded)
- **WHEN** the user views the Voice tab
- **THEN** it SHALL indicate that a model download is required to enable voice features
- **AND** it SHALL provide a shortcut to the model management section
