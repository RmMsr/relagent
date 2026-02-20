# api-health-check Specification

## Purpose
TBD - created by archiving change add-api-authentication-support. Update Purpose after archive.
## Requirements
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

### Requirement: Health Check Request Construction

The system SHALL make health check requests that validate authentication without consuming excessive API resources.

#### Scenario: Minimal health check payload
- **GIVEN** a health check is initiated
- **WHEN** the request is constructed
- **THEN** the request SHALL use the /chat/completions endpoint
- **AND** the request SHALL include a minimal message payload (e.g., single "ping" message)
- **AND** the request SHALL include authentication headers/cookies if configured

#### Scenario: Include authentication in health check
- **GIVEN** Basic Auth credentials are configured
- **WHEN** a health check request is made
- **THEN** the request SHALL include the "Authorization" header with Basic Auth credentials
- **AND** the health check SHALL validate both connectivity and authentication

#### Scenario: Follow redirects during health check
- **GIVEN** a health check is initiated
- **WHEN** the API responds with HTTP 302 redirect
- **THEN** the health check SHALL follow the redirect
- **AND** the response SHALL be analyzed for authentication requirements (see auth-detection spec)

### Requirement: Health Check Result Reporting

The system SHALL provide clear, actionable feedback on health check outcomes.

#### Scenario: Health check success - no auth required
- **GIVEN** a health check is performed
- **WHEN** the API responds with HTTP 200-299 without authentication challenges
- **THEN** the health check result SHALL be "Success ✓"
- **AND** the authentication type SHALL be set to "None"
- **AND** the settings UI SHALL indicate "Connected - No authentication required"

#### Scenario: Health check success - authenticated
- **GIVEN** a health check is performed with authentication credentials
- **WHEN** the API responds with HTTP 200-299
- **THEN** the health check result SHALL be "Success ✓"
- **AND** the authentication status SHALL be "Authenticated ✓"
- **AND** the settings UI SHALL indicate successful authentication

#### Scenario: Health check failure - authentication required
- **GIVEN** a health check is performed without credentials
- **WHEN** the API responds with HTTP 401 and WWW-Authenticate header
- **THEN** the health check result SHALL be "Authentication Required"
- **AND** the detected authentication type SHALL be shown (e.g., "Basic Auth required")
- **AND** the settings UI SHALL prompt the user to enter credentials

#### Scenario: Health check failure - form auth required
- **GIVEN** a health check is performed
- **WHEN** the API responds with HTTP 302 redirect to an HTML login form
- **THEN** the health check result SHALL be "Form Authentication Required"
- **AND** the settings UI SHALL display a "Login via Form" button
- **AND** the user SHALL be guided to authenticate via the form

#### Scenario: Health check failure - network error
- **GIVEN** a health check is performed
- **WHEN** the request fails due to network connectivity issues
- **THEN** the health check result SHALL be "Connection Failed"
- **AND** the error message SHALL indicate the network issue (e.g., "Cannot reach server")
- **AND** the user SHALL be advised to check URL and network connectivity

#### Scenario: Health check failure - invalid endpoint
- **GIVEN** a health check is performed
- **WHEN** the API responds with HTTP 404 Not Found
- **THEN** the health check result SHALL be "Invalid Endpoint"
- **AND** the error message SHALL indicate "/chat/completions endpoint not found"
- **AND** the user SHALL be advised to verify the base URL

### Requirement: Health Check Status Persistence

The system SHALL persist health check results for user reference across sessions.

#### Scenario: Display last health check result
- **GIVEN** a health check was performed and completed
- **WHEN** the user navigates away from settings and returns
- **THEN** the last health check result SHALL still be displayed
- **AND** the timestamp of the last check SHALL be shown (e.g., "Last checked: 2 minutes ago")

#### Scenario: Indicate stale health check
- **GIVEN** a health check was performed over 24 hours ago
- **WHEN** the user opens the settings page
- **THEN** the health check result SHALL be marked as stale (e.g., "Last checked: 2 days ago - retest recommended")
- **AND** the user SHALL be prompted to run a fresh health check

#### Scenario: Clear health check on configuration change
- **GIVEN** a health check result is displayed
- **WHEN** the user changes the API URL or model
- **THEN** the health check status SHALL change to "Pending..." or "Not tested"
- **AND** a new health check SHALL be triggered automatically (per earlier requirements)

### Requirement: Health Check Error Handling

The system SHALL handle health check failures gracefully without affecting app stability.

#### Scenario: Health check timeout
- **GIVEN** a health check is initiated
- **WHEN** the request does not complete within 30 seconds
- **THEN** the health check SHALL timeout
- **AND** the result SHALL indicate "Connection timeout - server may be slow or unreachable"
- **AND** the user SHALL be advised to retry or check server status

#### Scenario: Health check during offline mode
- **GIVEN** the device has no network connectivity
- **WHEN** a health check is triggered
- **THEN** the health check SHALL fail immediately
- **AND** the result SHALL indicate "No network connection"
- **AND** the health check SHALL not retry automatically until network is restored

#### Scenario: Malformed API response during health check
- **GIVEN** a health check is performed
- **WHEN** the API responds with HTTP 200 but invalid JSON body
- **THEN** the health check result SHALL be "Invalid Response"
- **AND** the error message SHALL indicate "Server returned malformed response - check API compatibility"
- **AND** the user SHALL be advised that the endpoint may not be OpenAI-compatible

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

