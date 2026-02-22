## ADDED Requirements

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
