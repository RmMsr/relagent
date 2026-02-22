## ADDED Requirements

### Requirement: API Key Configuration for Relagent Engine

The system SHALL allow users to enter and save an API key for the Relagent Engine backend. The key SHALL be stored in platform secure storage and associated with the current engine URL.

#### Scenario: API key input field visible in engine settings
- **WHEN** the user opens the settings page with the Relagent Engine backend selected
- **THEN** an API key input field SHALL be visible in the Engine authentication section
- **AND** the field SHALL be labeled "API Key"
- **AND** the field SHALL obscure the entered value (password-style)

#### Scenario: Save engine API key
- **GIVEN** the user has entered an API key in the engine settings
- **WHEN** the user presses Save
- **THEN** the API key SHALL be stored in platform secure storage keyed to the current engine URL
- **AND** `engineHasApiKey` SHALL be set to `true` in settings
- **AND** the API key SHALL NOT be written to SharedPreferences

#### Scenario: Saved API key indicated on reload
- **GIVEN** the user has previously saved an API key for the current engine URL
- **WHEN** the settings page is opened
- **THEN** the API key field SHALL be empty (not pre-filled)
- **AND** a hint SHALL indicate that an API key is saved (e.g., "API key saved")

#### Scenario: Clear engine API key
- **GIVEN** an API key is stored for the current engine URL
- **WHEN** the user clears the API key field and saves
- **THEN** the API key SHALL be removed from secure storage
- **AND** `engineHasApiKey` SHALL be set to `false`
- **AND** subsequent engine requests SHALL omit the `X-API-Key` header

### Requirement: API Key Configuration for OpenAI-Compatible Backend

The system SHALL allow users to enter and save an API key for the OpenAI-compatible backend. The key SHALL be stored in platform secure storage and associated with the current simple chat base URL.

#### Scenario: API key input field visible in simple chat settings
- **WHEN** the user opens the settings page with the OpenAI-compatible backend selected
- **THEN** an API key input field SHALL be visible in the API authentication section
- **AND** the field SHALL be labeled "API Key"
- **AND** the field SHALL obscure the entered value (password-style)

#### Scenario: Save simple chat API key
- **GIVEN** the user has entered an API key in the simple chat settings
- **WHEN** the user presses Save
- **THEN** the API key SHALL be stored in platform secure storage keyed to the current simple chat base URL
- **AND** `simpleChatHasApiKey` SHALL be set to `true` in settings
- **AND** the API key SHALL NOT be written to SharedPreferences

#### Scenario: Clear simple chat API key
- **GIVEN** an API key is stored for the current simple chat URL
- **WHEN** the user clears the API key field and saves
- **THEN** the API key SHALL be removed from secure storage
- **AND** `simpleChatHasApiKey` SHALL be set to `false`

### Requirement: Engine API Key Header Injection

The system SHALL inject the `X-API-Key` header into every Relagent Engine HTTP request when an API key is stored for the active engine URL.

#### Scenario: X-API-Key header added when key is stored
- **GIVEN** an API key is stored for the current engine URL
- **WHEN** any engine API request is made (messages, sessions, status, events)
- **THEN** the request SHALL include the header `X-API-Key: <stored-key>`

#### Scenario: No X-API-Key header without stored key
- **GIVEN** no API key is stored for the current engine URL
- **WHEN** an engine API request is made
- **THEN** the request SHALL NOT include an `X-API-Key` header

#### Scenario: API key and Basic Auth both injected when both configured
- **GIVEN** both Basic Auth credentials and an API key are stored for the current engine URL
- **WHEN** an engine API request is made
- **THEN** the request SHALL include both `Authorization: Basic …` and `X-API-Key: …` headers

### Requirement: OpenAI-Compatible API Key Header Injection

The system SHALL inject the `Authorization: Bearer <key>` header into every OpenAI-compatible HTTP request when an API key is stored for the active simple chat URL.

#### Scenario: Bearer token added when key is stored
- **GIVEN** an API key is stored for the current simple chat URL
- **WHEN** a chat completion request is made
- **THEN** the request SHALL include the header `Authorization: Bearer <stored-key>`

#### Scenario: Bearer token takes precedence over Basic Auth Authorization header
- **GIVEN** an API key is stored and Basic Auth is also configured for the same simple chat URL
- **WHEN** a chat completion request is made
- **THEN** the request SHALL include `Authorization: Bearer <key>` (not `Authorization: Basic …`)
- **AND** the request SHALL NOT send conflicting Authorization headers

#### Scenario: No Authorization header injected for API key without stored key
- **GIVEN** no API key is stored for the current simple chat URL and no Basic Auth is configured
- **WHEN** a chat completion request is made
- **THEN** the request SHALL NOT include an Authorization header

### Requirement: API Key Cleared on URL Change

The system SHALL clear stored API keys when the associated backend URL is changed, preventing credential leakage to a different endpoint.

#### Scenario: Engine API key cleared on engine URL change
- **GIVEN** an API key is stored for engine URL "http://server1:8000"
- **WHEN** the user changes the engine URL to "http://server2:8000" and saves
- **THEN** the API key for "http://server1:8000" SHALL be deleted from secure storage
- **AND** `engineHasApiKey` SHALL be set to `false`
- **AND** the user SHALL need to re-enter an API key for the new URL

#### Scenario: Simple chat API key cleared on URL change
- **GIVEN** an API key is stored for simple chat URL "http://localhost:1234/api/v1"
- **WHEN** the user changes the simple chat base URL and saves
- **THEN** the API key for the old URL SHALL be deleted from secure storage
- **AND** `simpleChatHasApiKey` SHALL be set to `false`
