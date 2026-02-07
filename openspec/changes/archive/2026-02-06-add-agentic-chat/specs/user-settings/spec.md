## ADDED Requirements

### Requirement: Engine URL Setting

The system SHALL provide a user setting to configure the Relagent Engine URL.

#### Scenario: Default engine URL

- **GIVEN** the app is freshly installed
- **WHEN** settings are loaded
- **THEN** the engine URL SHALL default to `http://localhost:8000/api/v1`

#### Scenario: Edit engine URL

- **GIVEN** the user opens the settings page
- **WHEN** the user enters a new Engine URL
- **THEN** the URL SHALL be validated for format
- **AND** the setting SHALL be saved

#### Scenario: Engine URL persistence

- **GIVEN** the user has configured a custom Engine URL
- **WHEN** the app is closed and reopened
- **THEN** the configured URL SHALL be restored

### Requirement: Engine Authentication Setting

The system SHALL provide settings to configure basic HTTP authentication for the engine.

#### Scenario: No authentication by default

- **GIVEN** the app is freshly installed
- **WHEN** settings are loaded
- **THEN** engine authentication SHALL be disabled (none)

#### Scenario: Enable basic authentication

- **GIVEN** the user opens the settings page
- **WHEN** the user selects "Basic" authentication type
- **THEN** username and password fields SHALL become available
- **AND** credentials SHALL be stored securely

#### Scenario: Basic auth credentials persistence

- **GIVEN** the user has configured basic auth credentials
- **WHEN** the app is closed and reopened
- **THEN** the authentication type and username SHALL be restored
- **AND** password SHALL be retrievable for API requests

#### Scenario: Disable authentication

- **GIVEN** basic authentication is currently enabled
- **WHEN** the user selects "None" for authentication type
- **THEN** credentials SHALL no longer be sent with requests
- **AND** stored credentials MAY be cleared

### Requirement: Settings Page Layout

The system SHALL organize engine settings separately from simple chat API settings.

#### Scenario: Engine settings section

- **GIVEN** the user opens the settings page
- **WHEN** the page is displayed
- **THEN** an "Engine" section SHALL be visible
- **AND** it SHALL contain Engine URL and authentication settings

#### Scenario: Simple chat settings section

- **GIVEN** the user opens the settings page
- **WHEN** the page is displayed
- **THEN** the existing "API" section for simple chat SHALL remain available
- **AND** both sections SHALL be clearly labeled
