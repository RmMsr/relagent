## MODIFIED Requirements

### Requirement: Health Check Execution

The system SHALL provide a health check mechanism to validate API endpoint configuration and authentication. Health checks SHALL only run for the currently active backend type.

#### Scenario: Health check on app startup
- **GIVEN** the app has a configured API endpoint saved in settings
- **WHEN** the app starts up
- **THEN** a health check SHALL be performed only for the currently selected backend
- **AND** the health check SHALL run asynchronously without blocking the UI
- **AND** the result SHALL be displayed in the settings page

#### Scenario: OpenAI health check skipped when engine is active
- **GIVEN** the selected backend is Relagent Engine
- **WHEN** a simple chat (OpenAI-compatible) health check is triggered
- **THEN** the health check SHALL be skipped
- **AND** no network request SHALL be made to the OpenAI-compatible endpoint

#### Scenario: Engine health check skipped when OpenAI is active
- **GIVEN** the selected backend is OpenAI-compatible
- **WHEN** an engine health check is triggered
- **THEN** the health check SHALL be skipped
- **AND** no network request SHALL be made to the engine endpoint

#### Scenario: Health check on URL change
- **GIVEN** the user is on the settings page
- **WHEN** the user changes the API base URL
- **AND** saves the settings
- **THEN** a health check SHALL be triggered automatically
- **AND** the result SHALL update the authentication status in real-time

#### Scenario: Health check on credential change
- **GIVEN** the user is on the settings page with authentication configured
- **WHEN** the user updates username, password, or re-authenticates via form
- **AND** saves the changes
- **THEN** a health check SHALL be triggered automatically
- **AND** the result SHALL validate the new credentials

#### Scenario: Manual health check via test button
- **GIVEN** the user is on the settings page
- **WHEN** the user clicks the "Test Connection" button
- **THEN** a health check SHALL be performed immediately
- **AND** the UI SHALL show a loading indicator during the test
- **AND** the result SHALL be displayed when complete

### Requirement: Health Check Integration with Chat Flow

The system SHALL use health check results to prevent chat errors and guide users proactively. The connection error banner SHALL provide both a retry action and a settings navigation action.

#### Scenario: Connection error banner with retry button
- **GIVEN** a health check has failed
- **WHEN** the connection error banner is displayed on the chat page
- **THEN** the banner SHALL include a "Retry" button
- **AND** the banner SHALL include a "Check Settings" button
- **AND** pressing "Retry" SHALL trigger an immediate health check for the active backend
- **AND** the banner SHALL update or dismiss based on the retry result

#### Scenario: Block chat when health check failed
- **GIVEN** the last health check failed with "Connection Failed" or "Invalid Endpoint"
- **WHEN** the user attempts to send a chat message
- **THEN** the chat SHALL be blocked
- **AND** an error message SHALL prompt the user to fix API configuration in settings
- **AND** the error SHALL reference the specific health check failure

#### Scenario: Prompt authentication before first chat
- **GIVEN** the health check detected authentication is required but user has not authenticated
- **WHEN** the user attempts to send a chat message
- **THEN** the chat SHALL be blocked
- **AND** a prompt SHALL guide the user to settings to authenticate
- **AND** the prompt SHALL specify the authentication type required (Basic or Form)

#### Scenario: Allow chat after successful health check
- **GIVEN** the health check succeeded with "Authenticated ✓" status
- **WHEN** the user sends a chat message
- **THEN** the chat SHALL proceed normally
- **AND** no additional health checks SHALL block the message

## ADDED Requirements

### Requirement: Health check recovery triggers data reload
When a health check transitions from a failure state to success, the system SHALL automatically trigger a data reload to synchronize with the backend.

#### Scenario: Engine health check recovery triggers reload
- **GIVEN** the engine health check previously failed (connection error, auth error, etc.)
- **WHEN** a subsequent health check succeeds
- **THEN** the connection error banner SHALL be dismissed
- **AND** the agentic chat provider SHALL reload message history
- **AND** the SSE provider SHALL reconnect to receive events

#### Scenario: Simple chat health check recovery dismisses banner
- **GIVEN** the simple chat (OpenAI) health check previously failed
- **WHEN** a subsequent health check succeeds
- **THEN** the connection error banner SHALL be dismissed

#### Scenario: Health check recovery on retry
- **GIVEN** a connection error banner is displayed with a "Retry" button
- **WHEN** the user presses "Retry" and the health check succeeds
- **THEN** the banner SHALL be dismissed
- **AND** for agentic chat, a data reload SHALL be triggered
