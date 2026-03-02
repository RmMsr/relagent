## Purpose

Provide a settings UI for configuring backend connections, managing API key credentials, and selecting/managing ASR and TTS voice models.

## Requirements

### Requirement: API Key Indicator Fields in Settings

The system SHALL persist a boolean indicator for each backend's API key status in SharedPreferences. These indicators reflect whether an API key is stored in secure storage for the current URL, without exposing the key itself.

#### Scenario: engineHasApiKey defaults to false
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** settings are loaded
- **THEN** `engineHasApiKey` SHALL be `false`

#### Scenario: simpleChatHasApiKey defaults to false
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** settings are loaded
- **THEN** `simpleChatHasApiKey` SHALL be `false`

#### Scenario: engineHasApiKey persists across restarts
- **GIVEN** the user has saved an API key for the current engine URL
- **WHEN** the app is closed and reopened
- **THEN** `engineHasApiKey` SHALL still be `true`
- **AND** the settings page SHALL show the "API key saved" indicator

#### Scenario: Indicator reset when API key is cleared
- **GIVEN** `engineHasApiKey` is `true`
- **WHEN** the user clears the API key and saves
- **THEN** `engineHasApiKey` SHALL be set to `false`

### Requirement: API Key Credential Binding to URL

The system SHALL treat API key credentials as attributes of their respective URL. Changing a URL SHALL invalidate and remove the credentials associated with the old URL.

#### Scenario: Engine URL change resets API key indicator
- **GIVEN** `engineHasApiKey` is `true` for the current engine URL
- **WHEN** the user changes the engine URL to a different value and saves
- **THEN** `engineHasApiKey` SHALL be set to `false`
- **AND** the old API key SHALL be cleared from secure storage

#### Scenario: Simple chat URL change resets API key indicator
- **GIVEN** `simpleChatHasApiKey` is `true` for the current simple chat URL
- **WHEN** the user changes the simple chat base URL and saves
- **THEN** `simpleChatHasApiKey` SHALL be set to `false`
- **AND** the old API key SHALL be cleared from secure storage

#### Scenario: API key indicator not included in settings JSON serialization as a secret
- **GIVEN** settings are serialized for persistence
- **WHEN** the JSON representation is written to SharedPreferences
- **THEN** `engineHasApiKey` and `simpleChatHasApiKey` boolean values SHALL be included
- **AND** no actual API key string value SHALL appear in the serialized output

### Requirement: Model Management Settings Section
The settings page SHALL include a "Voice Models" section for managing ASR and TTS models.

#### Scenario: Section visible on voice-capable platforms
- **GIVEN** the user opens the settings page on a platform with voice capabilities
- **WHEN** the page is displayed
- **THEN** a "Voice Models" section SHALL be visible
- **AND** it SHALL show the currently active ASR and TTS models (or "None" if no model selected)

#### Scenario: Section hidden on web
- **GIVEN** the user opens the settings page on web
- **WHEN** the page is displayed
- **THEN** the "Voice Models" section SHALL NOT be displayed

#### Scenario: Browse available models
- **WHEN** the user taps a "Browse Models" action in the Voice Models section
- **THEN** the system SHALL display the model catalog filtered by type (ASR or TTS)
- **AND** each entry SHALL show: display name, supported languages, download size, and streaming indicator (for ASR)

#### Scenario: Download model from catalog
- **WHEN** the user taps download on a catalog entry
- **THEN** the system SHALL start downloading the model
- **AND** it SHALL show download progress in the catalog entry
- **AND** the user SHALL be able to cancel the download

#### Scenario: Select active model
- **WHEN** the user taps on a downloaded model
- **THEN** the system SHALL set it as the active ASR or TTS model
- **AND** the selection SHALL persist across app restarts via SharedPreferences

#### Scenario: Delete downloaded model
- **WHEN** the user requests deletion of a downloaded model
- **THEN** the system SHALL remove the model files from storage
- **AND** if the model was active, the system SHALL clear the selection

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
- **THEN** the selection SHALL be cleared
- **AND** the system SHALL fall back to bundled model if available

### Requirement: Voice settings visible when available
The voice-related settings sections SHALL be conditionally visible based on platform voice capabilities and model availability.

#### Scenario: Voice settings visible when available
- **GIVEN** the user opens the settings page on a platform with voice capabilities
- **WHEN** the page is displayed
- **THEN** the voice mode selector SHALL be displayed
- **AND** the background listening duration setting SHALL be displayed
- **AND** TTS-related settings SHALL be displayed

#### Scenario: Voice mode selector indicates model requirement
- **GIVEN** no ASR model is available (neither bundled nor downloaded)
- **WHEN** the user views the voice mode selector
- **THEN** it SHALL indicate that a model download is required to enable voice features
- **AND** it SHALL provide a shortcut to the model management section
