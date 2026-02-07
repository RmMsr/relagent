# user-settings Specification

## Purpose
TBD - created by archiving change add-reliable-background-listening. Update Purpose after archive.
## Requirements
### Requirement: Background Listening Duration Setting
The system SHALL provide a user setting to configure the maximum duration for background listening sessions.

#### Scenario: Default duration is one hour
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** the settings are loaded
- **THEN** the background listening duration SHALL default to 1 hour

#### Scenario: User selects short durations
- **GIVEN** the user opens the settings page
- **WHEN** the user selects "5 minutes", "15 minutes", or "30 minutes" from the background listening duration dropdown
- **THEN** the setting SHALL be saved
- **AND** future listening sessions SHALL timeout after the selected duration

#### Scenario: User selects medium durations
- **GIVEN** the user opens the settings page
- **WHEN** the user selects "1 hour", "2 hours", "3 hours", or "6 hours" from the background listening duration dropdown
- **THEN** the setting SHALL be saved
- **AND** future listening sessions SHALL timeout after the selected duration

#### Scenario: User selects long durations
- **GIVEN** the user opens the settings page
- **WHEN** the user selects "12 hours" or "24 hours" from the background listening duration dropdown
- **THEN** the setting SHALL be saved
- **AND** future listening sessions SHALL timeout after the selected duration

#### Scenario: User selects unlimited duration
- **GIVEN** the user opens the settings page
- **WHEN** the user selects "Unlimited" from the background listening duration dropdown
- **THEN** the setting SHALL be saved
- **AND** future listening sessions SHALL NOT automatically timeout

#### Scenario: Duration setting persists across app restarts
- **GIVEN** the user has set background listening duration to 2 hours
- **WHEN** the app is closed
- **AND** the app is reopened
- **THEN** the background listening duration SHALL still be 2 hours

#### Scenario: Duration setting applies to new sessions only
- **GIVEN** a listening session is currently active
- **WHEN** the user changes the background listening duration setting
- **THEN** the current session SHALL continue with the previous duration
- **AND** new listening sessions SHALL use the updated duration

### Requirement: Background Listening Duration Options
The system SHALL provide exactly ten duration options for background listening.

#### Scenario: Available duration options
- **GIVEN** the user opens the background listening duration setting
- **WHEN** the dropdown is displayed
- **THEN** the following options SHALL be available:
  - 5 minutes
  - 15 minutes
  - 30 minutes
  - 1 hour
  - 2 hours
  - 3 hours
  - 6 hours
  - 12 hours
  - 24 hours
  - Unlimited

#### Scenario: Duration values are immutable
- **GIVEN** the user views the background listening duration setting
- **WHEN** the user attempts to enter a custom duration
- **THEN** custom input SHALL NOT be possible
- **AND** only the predefined options SHALL be selectable

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

### Requirement: Chat Backend Selection
The system SHALL allow users to select between two chat backend types:
- **OpenAI-compatible**: Any server implementing the OpenAI chat completions API
- **Relagent Engine**: The full-featured Relagent backend with persistence and agentic capabilities

The selected backend type MUST be persisted and restored on app restart.
Both backend URLs MUST be stored independently so users can switch without losing configuration.
The router MUST display the appropriate chat page based on the selected backend.

#### Scenario: User selects OpenAI-compatible backend
- **GIVEN** the user is on the settings page
- **WHEN** the user selects "OpenAI-compatible" backend option
- **THEN** the selection is persisted
- **AND** navigating to the chat shows the simple chat page

#### Scenario: User selects Relagent Engine backend
- **GIVEN** the user is on the settings page
- **WHEN** the user selects "Relagent Engine" backend option
- **THEN** the selection is persisted
- **AND** navigating to the chat shows the agentic chat page

#### Scenario: User switches between backends
- **GIVEN** the user has configured both backend URLs
- **WHEN** the user switches from one backend type to another
- **THEN** the previous backend's configuration is preserved
- **AND** the chat page changes to match the selected backend

