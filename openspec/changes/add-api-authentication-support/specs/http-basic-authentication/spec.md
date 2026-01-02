# http-basic-authentication

## Purpose

Enable API connections requiring HTTP Basic authentication using username and password credentials stored securely.

## ADDED Requirements

### Requirement: Basic Authentication Header Construction

The system SHALL add HTTP Basic authentication headers to API requests when credentials are configured.

#### Scenario: Add Basic Auth header with credentials
- **GIVEN** the user has configured username "testuser" and password "testpass" for the API
- **WHEN** a chat completion request is made to the API
- **THEN** the request SHALL include an "Authorization" header
- **AND** the header value SHALL be "Basic " followed by base64-encoded "testuser:testpass"
- **AND** the request SHALL be sent to the chat completions endpoint

#### Scenario: No auth header without credentials
- **GIVEN** the user has NOT configured authentication credentials
- **WHEN** a chat completion request is made to the API
- **THEN** the request SHALL NOT include an "Authorization" header
- **AND** the request SHALL be sent normally (unauthenticated)

#### Scenario: Update auth header when credentials change
- **GIVEN** the user has previously configured credentials
- **WHEN** the user updates the password in settings
- **AND** a subsequent chat completion request is made
- **THEN** the new password SHALL be used in the Authorization header
- **AND** the old credentials SHALL NOT be used

### Requirement: Basic Authentication Settings UI

The system SHALL provide UI controls for entering and managing HTTP Basic authentication credentials.

#### Scenario: Display username and password fields
- **GIVEN** the API requires HTTP Basic authentication (detected via 401 + WWW-Authenticate header)
- **WHEN** the user opens the settings page
- **THEN** username and password input fields SHALL be visible in the Authentication section
- **AND** the fields SHALL be clearly labeled "Username" and "Password"

#### Scenario: Password field obscured
- **GIVEN** the user is viewing the Basic Auth password field
- **WHEN** the password field is displayed
- **THEN** the password characters SHALL be obscured (shown as dots or asterisks)
- **AND** the user SHALL have an option to toggle password visibility

#### Scenario: Save Basic Auth credentials
- **GIVEN** the user has entered username "apiuser" and password "secret123"
- **WHEN** the user saves the settings
- **THEN** the username SHALL be persisted to SharedPreferences
- **AND** the password SHALL be persisted to secure storage (not SharedPreferences)
- **AND** both SHALL be associated with the current API URL

#### Scenario: Load saved credentials
- **GIVEN** the user has previously saved Basic Auth credentials
- **WHEN** the settings page is opened
- **THEN** the username field SHALL be pre-filled with the saved username
- **AND** the password field SHALL be empty (not pre-filled for security)
- **AND** a hint SHALL indicate that the password is saved

### Requirement: Basic Authentication Error Handling

The system SHALL detect and handle authentication failures gracefully.

#### Scenario: Authentication failure on 401 response
- **GIVEN** a chat request is made with Basic Auth credentials
- **WHEN** the API returns HTTP 401 Unauthorized
- **THEN** the system SHALL detect the authentication failure
- **AND** the user SHALL be shown a re-authentication prompt
- **AND** the error message SHALL indicate "Authentication failed - please check your credentials"

#### Scenario: Re-authentication after failure
- **GIVEN** a chat request failed with 401 Unauthorized
- **WHEN** the user enters new credentials in the re-authentication prompt
- **AND** saves the credentials
- **THEN** the original chat request SHALL be automatically retried with new credentials
- **AND** the chat SHALL continue normally if authentication succeeds

#### Scenario: Invalid credentials warning
- **GIVEN** the user is entering Basic Auth credentials
- **WHEN** the health check test fails with 401
- **THEN** the UI SHALL display "Invalid username or password" message
- **AND** the user SHALL be prompted to correct the credentials
- **AND** the credentials SHALL NOT be saved until health check succeeds

### Requirement: Basic Authentication Credential Management

The system SHALL allow users to view, update, and clear Basic Auth credentials.

#### Scenario: Update username only
- **GIVEN** the user has saved credentials with username "olduser" and password "pass123"
- **WHEN** the user changes the username to "newuser" without changing password
- **AND** saves settings
- **THEN** the username SHALL be updated to "newuser"
- **AND** the password SHALL remain "pass123" (unchanged)

#### Scenario: Update password only
- **GIVEN** the user has saved credentials
- **WHEN** the user enters a new password without changing username
- **AND** saves settings
- **THEN** the new password SHALL be stored in secure storage
- **AND** the username SHALL remain unchanged

#### Scenario: Clear credentials
- **GIVEN** the user has saved Basic Auth credentials
- **WHEN** the user clicks "Clear Credentials" or "Logout" button in settings
- **THEN** both username and password SHALL be removed from storage
- **AND** the username field SHALL be empty
- **AND** the password hint SHALL disappear
- **AND** the authentication status SHALL change to "Not authenticated"

#### Scenario: Credentials cleared on URL change
- **GIVEN** credentials are stored for "https://api1.example.com"
- **WHEN** the user changes the API URL to "https://api2.example.com"
- **THEN** the stored credentials SHALL be automatically cleared
- **AND** the username and password fields SHALL be empty
- **AND** the user SHALL be prompted to authenticate if the new API requires auth
