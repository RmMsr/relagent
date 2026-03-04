## ADDED Requirements

### Requirement: Reference Voice Persistence
The system SHALL persist the user's reference voice selection and custom voice library in SharedPreferences.

#### Scenario: ttsReferenceVoicePath defaults to null
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** settings are loaded
- **THEN** `ttsReferenceVoicePath` SHALL be `null`

#### Scenario: ttsReferenceVoicePath persists across restarts
- **GIVEN** the user has selected a reference voice
- **WHEN** the app is closed and reopened
- **THEN** `ttsReferenceVoicePath` SHALL still hold the previously selected path

#### Scenario: ttsCustomVoiceSamples defaults to empty list
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** settings are loaded
- **THEN** `ttsCustomVoiceSamples` SHALL be an empty list

#### Scenario: ttsCustomVoiceSamples persists across restarts
- **GIVEN** the user has imported one or more custom voice samples
- **WHEN** the app is closed and reopened
- **THEN** all previously imported sample paths SHALL still be present in `ttsCustomVoiceSamples`

## MODIFIED Requirements

### Requirement: Voice settings visible when available
The voice-related settings sections SHALL be conditionally visible based on platform voice capabilities and model availability.

#### Scenario: Voice settings visible when available
- **GIVEN** the user opens the settings page on a platform with voice capabilities
- **WHEN** the page is displayed
- **THEN** the voice mode selector SHALL be displayed
- **AND** the background listening duration setting SHALL be displayed
- **AND** TTS-related settings SHALL be displayed
- **AND** if the active TTS model supports voice cloning, a reference voice picker row SHALL be displayed

#### Scenario: Voice mode selector indicates model requirement
- **GIVEN** no ASR model is available (neither bundled nor downloaded)
- **WHEN** the user views the voice mode selector
- **THEN** it SHALL indicate that a model download is required to enable voice features
- **AND** it SHALL provide a shortcut to the model management section
