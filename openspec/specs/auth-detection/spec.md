# auth-detection Specification

## Purpose
TBD - created by archiving change add-api-authentication-support. Update Purpose after archive.
## Requirements
### Requirement: HTTP Basic Auth Detection

The system SHALL detect when an API requires HTTP Basic authentication based on HTTP 401 responses with WWW-Authenticate header.

#### Scenario: Detect Basic Auth from WWW-Authenticate header
- **GIVEN** a request is made to the chat completions endpoint
- **WHEN** the API responds with HTTP 401 Unauthorized
- **AND** the response includes a "WWW-Authenticate" header with value starting with "Basic"
- **THEN** the system SHALL identify the authentication type as HTTP Basic
- **AND** the settings SHALL be updated to reflect "Basic Auth required"

#### Scenario: Detect Basic Auth realm
- **GIVEN** a request returns HTTP 401 with WWW-Authenticate header
- **WHEN** the header value is 'Basic realm="API Authentication"'
- **THEN** the system SHALL extract the realm value
- **AND** the realm SHALL be displayed to the user (e.g., "Basic Auth required for: API Authentication")

#### Scenario: Distinguish Basic from other auth schemes
- **GIVEN** a request returns HTTP 401 with WWW-Authenticate header
- **WHEN** the header value starts with "Bearer" or "Digest" (not "Basic")
- **THEN** the system SHALL NOT identify this as Basic authentication
- **AND** an error SHALL indicate unsupported authentication scheme

### Requirement: Form-Based Auth Detection

The system SHALL detect when an API requires form-based authentication based on HTTP 302 redirects to HTML content.

#### Scenario: Detect form auth from redirect to HTML page
- **GIVEN** a request is made to the chat completions endpoint
- **WHEN** the API responds with HTTP 302 redirect
- **AND** following the redirect results in a response with Content-Type "text/html"
- **THEN** the system SHALL identify the authentication type as form-based
- **AND** the settings SHALL be updated to reflect "Form Auth required"

#### Scenario: Detect form auth from redirect to HTML (alternate content type)
- **GIVEN** a request is made to the chat completions endpoint
- **WHEN** the API responds with HTTP 302 redirect
- **AND** following the redirect results in Content-Type "application/html"
- **THEN** the system SHALL identify the authentication type as form-based

#### Scenario: Ignore non-HTML redirects
- **GIVEN** a request is made to the chat completions endpoint
- **WHEN** the API responds with HTTP 302 redirect
- **AND** following the redirect results in Content-Type "application/json"
- **THEN** the system SHALL NOT identify this as form authentication
- **AND** the redirect SHALL be followed normally without triggering auth flow

#### Scenario: Capture login form URL from redirect
- **GIVEN** form-based authentication is detected via 302 redirect
- **WHEN** the redirect Location header points to "https://api.example.com/login"
- **THEN** the system SHALL store the login form URL
- **AND** the login form URL SHALL be used when displaying the WebView for authentication

### Requirement: No Authentication Detection

The system SHALL detect when an API does not require authentication based on successful responses.

#### Scenario: Detect no auth required on 200 response
- **GIVEN** a request is made to the chat completions endpoint without authentication
- **WHEN** the API responds with HTTP 200 OK
- **AND** the response contains valid JSON with expected structure
- **THEN** the system SHALL identify the authentication type as "None"
- **AND** the settings SHALL reflect "No authentication required"

#### Scenario: Detect authenticated state
- **GIVEN** a request is made with authentication credentials
- **WHEN** the API responds with HTTP 200 OK
- **THEN** the system SHALL confirm authentication is successful
- **AND** the authentication status SHALL be "Authenticated ✓"

### Requirement: Authentication Detection Persistence

The system SHALL persist detected authentication types across app sessions.

#### Scenario: Save detected auth type to settings
- **GIVEN** authentication type is detected as "Basic" via 401 response
- **WHEN** the detection occurs
- **THEN** the authentication type SHALL be saved to SharedPreferences
- **AND** the saved value SHALL be "basic" (or equivalent enum value)

#### Scenario: Load saved auth type on app restart
- **GIVEN** the authentication type was previously detected and saved as "Form"
- **WHEN** the app restarts
- **THEN** the settings SHALL load with authentication type "Form"
- **AND** the appropriate UI controls SHALL be displayed (e.g., "Login via Form" button)

#### Scenario: Reset auth type on URL change
- **GIVEN** the authentication type is saved as "Basic" for current API
- **WHEN** the user changes the API URL to a different endpoint
- **THEN** the authentication type SHALL reset to "None" (unknown)
- **AND** a new health check SHALL detect the auth type for the new endpoint

### Requirement: Authentication Detection Error Handling

The system SHALL handle ambiguous or unsupported authentication scenarios gracefully.

#### Scenario: Unsupported authentication scheme
- **GIVEN** a request returns HTTP 401 with WWW-Authenticate header
- **WHEN** the header value is "Bearer" or "Digest" or "OAuth"
- **THEN** the system SHALL show error "Unsupported authentication type detected"
- **AND** the error message SHALL suggest using Basic Auth or form-based auth instead
- **AND** the user SHALL be directed to check API documentation

#### Scenario: Multiple authentication methods offered
- **GIVEN** a request returns HTTP 401
- **WHEN** the response includes multiple WWW-Authenticate headers (e.g., "Basic" and "Bearer")
- **THEN** the system SHALL prioritize Basic authentication (supported)
- **AND** the user SHALL be informed that Basic Auth will be used

#### Scenario: Missing Content-Type on redirect
- **GIVEN** a request returns HTTP 302 redirect
- **WHEN** following the redirect results in a response without Content-Type header
- **THEN** the system SHALL NOT assume form authentication
- **AND** the system SHALL treat it as an error (malformed API response)

### Requirement: Re-detection on Authentication Failure

The system SHALL re-detect authentication requirements when authentication fails during normal operation.

#### Scenario: Re-detect after credential change
- **GIVEN** the authentication type is currently "Basic"
- **WHEN** a chat request with Basic Auth credentials returns HTTP 401
- **THEN** the system SHALL re-examine the WWW-Authenticate header
- **AND** confirm the authentication type is still "Basic"
- **AND** prompt the user to update credentials (not change auth type)

#### Scenario: Detect auth type change after endpoint update
- **GIVEN** the authentication type was "None" for the previous API
- **WHEN** the API is updated and now returns 401 with WWW-Authenticate
- **THEN** the system SHALL detect the new authentication requirement
- **AND** update the authentication type accordingly
- **AND** prompt the user to configure authentication

#### Scenario: Detect form auth after Basic Auth failure
- **GIVEN** the system attempts Basic Auth based on previous detection
- **WHEN** the request returns HTTP 302 redirect to HTML (not 401)
- **THEN** the system SHALL re-detect authentication type as "Form"
- **AND** clear the stored Basic Auth credentials
- **AND** prompt the user to authenticate via form instead

